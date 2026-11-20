import Foundation
#if canImport(OSLog)
    import OSLog
#endif

// MARK: - Public surface

/// Where the lead form is in its life. Carries only a state and, once submitted, the lead id:
/// never the preparation token, a contact value, or an answer.
@_spi(InteractiveExperience)
public enum LeadFormState: Equatable {
    case idle
    case preparing
    case prepared
    case activating
    case readyToShow
    case visible
    case submitting
    case submitted(leadId: String)
    case failed(retryable: Bool)
    case expired
    case disposed
}

/// Why the form asks the app to open a web address.
@_spi(InteractiveExperience)
public enum LeadFormLinkPurpose: String, Equatable, Sendable {
    /// The form's privacy policy, available any time the form is shown.
    case privacyPolicy = "privacy_policy"
    /// The advertiser's website, offered only after the form was submitted.
    case websiteCta = "website_cta"
}

/// Receives the controller's state changes and the form's requests. Held weakly.
///
/// Experimental: import with `@_spi(InteractiveExperience) import AdMoai`.
@_spi(InteractiveExperience)
@MainActor
public protocol LeadFormControllerDelegate: AnyObject {
    func leadFormController(_ controller: LeadFormController, didChange state: LeadFormState)
    func leadFormControllerDidRequestClose(_ controller: LeadFormController)
    /// The form asks the app to open `url` (always `https`). Open it outside the form, for example
    /// in an `SFSafariViewController`: the form and the answers typed so far stay as they are.
    /// Do not add the form's identifiers or any value to it.
    func leadFormController(_ controller: LeadFormController, openExternalURL url: URL, purpose: LeadFormLinkPurpose)
}

@_spi(InteractiveExperience)
public extension LeadFormControllerDelegate {
    /// Ignores the request: the link is not opened.
    func leadFormController(_: LeadFormController, openExternalURL _: URL, purpose _: LeadFormLinkPurpose) {}
}

// MARK: - Transport seam

/// What the controller needs from the surface that hosts the form page. Production is
/// ``SecureFormWebView``; unit tests drive the controller with a fake.
@MainActor
protocol LeadFormTransport: AnyObject {
    /// Receives each string the page posts, already filtered to the form's own frame and origin.
    var onMessage: ((String) -> Void)? { get set }
    /// The page could not be loaded, or its renderer was lost.
    var onLoadFailed: (() -> Void)? { get set }
    func load(_ url: URL)
    func send(_ message: String)
    func teardown()
}

// MARK: - Controller

/// Drives one Lead Generation form: prepares it in the background, activates it when the viewer
/// taps, and reports its state.
///
/// Create it with ``AdMoai/makeLeadFormController(for:presentation:)``. Call ``dispose()`` when the
/// form is no longer needed; releasing the controller also tears the page down, but without telling
/// it.
///
/// When the form is activated the controller asks the app's ``LeadFormValueProvider`` for the
/// values the form requests (it waits 1.5 seconds in all) and sends them to the form once. The
/// values are never logged, never passed to the delegate and not kept. Form events fire the
/// tracking URL the activation listed, once each; links the form requests reach the delegate.
///
/// At most two forms per app prepare in the background without having been opened: a further
/// ``prepare()`` waits (state stays `idle`) until one is opened, disposed or fails. ``open()``
/// never waits.
///
/// When the app disables interactive experiences, switches the provider, or changes the user id,
/// every live controller is disposed.
///
/// Experimental: import with `@_spi(InteractiveExperience) import AdMoai`.
@_spi(InteractiveExperience)
@MainActor
public final class LeadFormController {
    public weak var delegate: LeadFormControllerDelegate?
    public private(set) var state: LeadFormState = .idle
    public let presentation: LeadFormPresentation

    /// Minted per controller; reaches the page only in the launch URL's fragment.
    let channel: String
    /// The platform container the app shows, created on demand (see `LeadFormView`).
    var surfaceHost: AnyObject?
    let transport: LeadFormTransport

    private let experience: LeadGenerationExperience
    private let logger: Logger
    private let now: () -> Date
    private let optIn: InteractiveExperienceBox
    private let generation: Int
    private let prefillTimeoutMs: Int
    private let tracking: LeadFormTracking

    private var exchanged = Set<String>()
    private var context = LeadFormBridge.Context()
    private var requestedKeys = Set<StandardAttributeKey>()
    private var activated = false
    private var bridgeReadySeen = false
    private var openRequested = false
    private var retryIsActivation = false
    private var retryIsReload = false
    private var surfaceVisible = false
    private var hasBeenVisible = false
    private var prefillStarted = false
    private var isDisposed = false

    init(
        experience: LeadGenerationExperience,
        presentation: LeadFormPresentation,
        transport: LeadFormTransport,
        logger: Logger,
        now: @escaping () -> Date = Date.init,
        optIn: InteractiveExperienceBox = InteractiveExperienceBox(),
        prefillTimeoutMs: Int = LeadFormBridge.Limits.prefillLookupTimeoutMs,
        fireTracking: @escaping LeadFormTracking.Send = { _, done in done(true) },
        retryDelaysMs: [Int] = LeadFormTracking.defaultRetryDelaysMs
    ) {
        self.experience = experience
        self.presentation = presentation
        self.transport = transport
        self.logger = logger
        self.now = now
        self.optIn = optIn
        self.prefillTimeoutMs = prefillTimeoutMs
        generation = optIn.generation
        tracking = LeadFormTracking(send: fireTracking, retryDelaysMs: retryDelaysMs, logger: logger)
        channel = Self.mintChannel()
        transport.onMessage = { [weak self] text in self?.receive(text) }
        transport.onLoadFailed = { [weak self] in self?.loadFailed() }
        optIn.register(self)
    }

    deinit {
        // Dropping the controller must not leave a page running. `teardown` is main-actor work and
        // a deinit is not, so it is handed over; the gate learns the slot is free the same way.
        let transport = transport
        let gate = optIn.hiddenFormGate
        Task { @MainActor in
            transport.onMessage = nil
            transport.onLoadFailed = nil
            transport.teardown()
            gate.slotMayHaveFreed()
        }
    }

    // MARK: Commands

    /// Starts preparing the form in the background. Harmless when already started.
    ///
    /// Preparing in the background is bounded: when two other forms are already preparing or
    /// prepared without having been opened, this one stays `idle` and starts when one of them is
    /// opened, disposed or fails.
    public func prepare() {
        guard !isDisposed, state == .idle else { return }
        guard now() < experience.expiresAt else {
            set(.expired)
            return
        }
        if optIn.hiddenFormGate.acquire(self) {
            startPreparing()
        }
    }

    /// The gate has a slot for this form after it waited.
    func startQueuedPrepare() {
        guard !isDisposed, state == .idle else {
            optIn.hiddenFormGate.release(self)
            return
        }
        guard now() < experience.expiresAt else {
            set(.expired)
            return
        }
        startPreparing()
    }

    private func startPreparing() {
        set(.preparing)
        transport.load(launchURL())
    }

    /// The viewer tapped: activates the form, preparing it first when that has not happened yet
    /// (the same load is reused, never a second one).
    public func open() {
        guard !isDisposed else { return }
        // Opening is not hidden prewarm: the form stops counting against the bound, or leaves its queue.
        optIn.hiddenFormGate.release(self)
        switch state {
        case .idle:
            openRequested = true
            guard now() < experience.expiresAt else {
                set(.expired)
                return
            }
            startPreparing()
        case .preparing:
            openRequested = true
            expireIfPastDeadline()
        case .prepared:
            openRequested = true
            // A prepared form is not opened with an authorization that has lapsed since.
            guard !expireIfPastDeadline() else { return }
            sendActivate()
        default:
            break
        }
    }

    /// Tries again after a failure the form said is retryable.
    public func retry() {
        guard !isDisposed, case .failed(retryable: true) = state else { return }
        if retryIsReload {
            // No page was listening: load it again; its bridge_ready starts the exchange.
            retryIsReload = false
            guard !expireIfPastDeadline() else { return }
            set(.preparing)
            transport.load(launchURL())
        } else if retryIsActivation {
            retryIsActivation = false
            sendActivate()
        } else {
            set(.preparing)
            send(.retryPrepare)
        }
    }

    /// Moves to `expired` when the descriptor's deadline has passed. Nothing is sent.
    @discardableResult
    private func expireIfPastDeadline() -> Bool {
        guard now() >= experience.expiresAt else { return false }
        set(.expired)
        return true
    }

    /// Ends the form: tells the page when it is listening, releases the surface. Idempotent; after
    /// it every call and every incoming message is ignored and the delegate hears nothing more.
    public func dispose() {
        guard !isDisposed else { return }
        if bridgeReadySeen,
           let text = try? AppMessage.dispose.encode(instanceId: experience.formInstanceId, channel: channel)
        {
            transport.send(text)
        }
        isDisposed = true
        transport.onMessage = nil
        transport.onLoadFailed = nil
        transport.teardown()
        state = .disposed
        optIn.hiddenFormGate.release(self)
        delegate?.leadFormController(self, didChange: .disposed)
    }

    // MARK: Surface visibility (called by the container)

    func surfaceDidBecomeVisible() {
        guard !isDisposed else { return }
        surfaceVisible = true
        showIfReady()
    }

    func surfaceDidBecomeHidden() {
        guard !isDisposed else { return }
        surfaceVisible = false
        guard state == .visible else { return }
        set(.readyToShow)
        send(.becameHidden)
    }

    private func showIfReady() {
        guard state == .readyToShow else { return }
        hasBeenVisible = true
        set(.visible)
        send(.becameVisible)
    }

    // MARK: Incoming

    private func receive(_ text: String) {
        guard !isDisposed else { return }
        let result = LeadFormBridge.validateIncoming(
            text,
            expected: experience.formInstanceId,
            channel: channel,
            exchanged: exchanged,
            context: context
        )
        switch result {
        case let .failure(rejection):
            logger.warning("Lead form bridge refused a message: \(rejection.description, privacy: .public)")
            // A page that speaks a bridge version this SDK does not: the form is unavailable on this
            // app version. Nothing was sent, so the token never left.
            if rejection.isUnsupportedBridgeVersion, !isFinished {
                set(.failed(retryable: false))
            }
        case let .success(message):
            exchanged.insert(message.wireType)
            handle(message)
            // Each answer closes one `submitting`: a second answer, or one after a failure with no
            // new `submitting`, is refused as out of order.
            switch message {
            case .submitted, .submitFailed: exchanged.remove("submitting")
            default: break
            }
        }
    }

    /// The page failed to load or its renderer was lost. After activation the answers typed so far
    /// are gone, so it is final; before, nothing was typed and loading again is safe.
    private func loadFailed() {
        guard !isDisposed, !isFinished else { return }
        if activated {
            set(.failed(retryable: false))
            return
        }
        switch state {
        case .preparing, .prepared, .activating:
            retryIsReload = true
            set(.failed(retryable: true))
        default:
            break
        }
    }

    private var isFinished: Bool {
        switch state {
        case .failed(retryable: false), .expired, .disposed, .submitted: true
        default: false
        }
    }

    private func handle(_ message: RuntimeMessage) {
        switch message {
        case .bridgeReady:
            handleBridgeReady()
        case .prepared:
            guard state == .preparing else { return }
            set(.prepared)
            if openRequested {
                sendActivate()
            }
        case let .activated(_, keys, events):
            guard state == .activating, !activated else { return }
            activated = true
            requestedKeys = Set(keys)
            context.activatedEvents = Set(events.keys)
            tracking.activated(events: events)
            startPrefill()
        case .prefillApplied:
            guard state == .activating, activated else { return }
            set(.readyToShow)
            if surfaceVisible {
                showIfReady()
            }
        case let .prepareFailed(code, retryable):
            guard state == .preparing || state == .activating else { return }
            if code == .expired {
                set(.expired)
                return
            }
            retryIsActivation = state == .activating
            // `error-codes.json` decides which codes can ever be retried; the form can only narrow it.
            set(.failed(retryable: retryable && code.isRetryable))
        case let .fatalError(code):
            guard !isFinished else { return }
            set(code == .expired ? .expired : .failed(retryable: false))
        case .requestClose:
            delegate?.leadFormControllerDidRequestClose(self)
        case let .requestExternalURL(purpose, url):
            delegate?.leadFormController(self, openExternalURL: url, purpose: purpose.linkPurpose)
        case let .event(name):
            tracking.event(name)
        case .submitting:
            guard hasBeenVisible, state == .visible || state == .readyToShow else { return }
            set(.submitting)
        case .submitFailed:
            guard state == .submitting else { return }
            set(surfaceVisible ? .visible : .readyToShow)
        case let .submitted(leadId, _):
            guard state == .submitting else { return }
            set(.submitted(leadId: leadId))
        }
    }

    /// The first `bridge_ready` is answered with `initialize`. A later one means the page reloaded:
    /// before activation it is answered again; after, the answers typed so far are gone, so the
    /// controller fails without a retry.
    private func handleBridgeReady() {
        let wasSeen = bridgeReadySeen
        bridgeReadySeen = true
        switch state {
        case .preparing, .prepared, .activating:
            break
        case .readyToShow, .visible, .submitting:
            if wasSeen {
                set(.failed(retryable: false))
            }
            return
        default:
            return
        }
        if activated {
            set(.failed(retryable: false))
            return
        }
        retryIsActivation = false
        set(.preparing)
        send(.initialize(preparationToken: experience.preparationToken, presentation: presentation))
    }

    // MARK: Outgoing

    private func sendActivate() {
        set(.activating)
        send(.activate)
    }

    private func send(_ message: AppMessage) {
        do {
            let text = try message.encode(
                instanceId: experience.formInstanceId,
                channel: channel,
                allowedPrefillKeys: requestedKeys
            )
            exchanged.insert(message.wireType)
            transport.send(text)
        } catch {
            let reason = (error as? BridgeRejection)?.description ?? "not encodable"
            logger
                .warning(
                    "Lead form bridge could not send \(message.wireType, privacy: .public): \(reason, privacy: .public)"
                )
            if !isFinished {
                set(.failed(retryable: false))
            }
        }
    }

    // MARK: Prefill

    /// Asks the app's provider for the requested values it holds, then sends `prefill` once.
    /// With nothing to ask, it is sent at once.
    private func startPrefill() {
        guard !prefillStarted else { return }
        prefillStarted = true
        let generation = generation
        guard let provider = optIn.provider(forGeneration: generation) else {
            send(.prefill(values: [:]))
            return
        }
        let keys = requestedKeys.intersection(provider.availableKeys)
        guard !keys.isEmpty else {
            send(.prefill(values: [:]))
            return
        }
        let timeoutMs = prefillTimeoutMs
        Task { [weak self] in
            let values = await LeadFormPrefill.lookup(keys: keys, provider: provider, timeoutMs: timeoutMs)
            self?.sendPrefill(values, generation: generation)
        }
    }

    /// A result for an older opt-in or user, or for a form that ended, is discarded unsent.
    private func sendPrefill(_ values: [StandardAttributeKey: String], generation: Int) {
        guard !isDisposed, generation == optIn.generation, state == .activating else { return }
        send(.prefill(values: values))
    }

    private func set(_ newState: LeadFormState) {
        guard !isDisposed, newState != state else { return }
        state = newState
        switch newState {
        case .failed, .expired:
            // A form that can no longer be shown stops counting against the hidden-form bound.
            optIn.hiddenFormGate.release(self)
        default:
            break
        }
        delegate?.leadFormController(self, didChange: newState)
    }

    // MARK: Helpers

    private func launchURL() -> URL {
        guard var components = URLComponents(url: experience.launchUrl, resolvingAgainstBaseURL: false) else {
            return experience.launchUrl
        }
        components.fragment = "instanceId=\(experience.formInstanceId)&channel=\(channel)"
        return components.url ?? experience.launchUrl
    }

    private static func mintChannel() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        var generator = SystemRandomNumberGenerator()
        return String((0 ..< 32).map { _ in alphabet[Int.random(in: 0 ..< alphabet.count, using: &generator)] })
    }
}

// MARK: - Factory

@MainActor
public extension AdMoai {
    /// Creates the controller for one Lead Generation form, or `nil` when the app did not opt in
    /// (``enableInteractiveExperiences(valueProvider:)``) or the platform has no secure form view.
    ///
    /// Experimental: import with `@_spi(InteractiveExperience) import AdMoai`.
    @_spi(InteractiveExperience)
    func makeLeadFormController(
        for experience: LeadGenerationExperience,
        presentation: LeadFormPresentation
    ) -> LeadFormController? {
        guard interactiveExperienceBox.isEnabled else { return nil }
        #if canImport(WebKit)
            return LeadFormController(
                experience: experience,
                presentation: presentation,
                transport: SecureFormWebView(launchURL: experience.launchUrl, logger: config.logger),
                logger: config.logger,
                optIn: interactiveExperienceBox,
                fireTracking: { url, done in dispatchTracking(url: url.absoluteString, completion: done) }
            )
        #else
            return nil
        #endif
    }
}

extension ExternalURLPurpose {
    var linkPurpose: LeadFormLinkPurpose {
        switch self {
        case .privacyPolicy: .privacyPolicy
        case .websiteCta: .websiteCta
        }
    }
}

// MARK: - Hidden-form bound

/// Counts the forms that are preparing or prepared without ever having been opened, and queues the
/// ones past the bound. Owned by ``InteractiveExperienceBox``, so every copy of `AdMoai` shares it.
@MainActor
final class HiddenFormGate {
    private struct Entry {
        weak var controller: LeadFormController?
    }

    private let limit: Int
    private var counted: [Entry] = []
    private var queued: [Entry] = []

    nonisolated init(limit: Int = LeadFormBridge.Limits.maxHiddenPreparedForms) {
        self.limit = limit
    }

    /// True when `controller` may start preparing now (it holds a slot); false when it was queued
    /// and ``LeadFormController/startQueuedPrepare()`` will be called when a slot frees.
    func acquire(_ controller: LeadFormController) -> Bool {
        prune()
        if counted.contains(where: { $0.controller === controller }) {
            return true
        }
        if counted.count < limit {
            counted.append(Entry(controller: controller))
            return true
        }
        if !queued.contains(where: { $0.controller === controller }) {
            queued.append(Entry(controller: controller))
        }
        return false
    }

    /// `controller` was opened, disposed or failed: it holds no slot and waits for none.
    func release(_ controller: LeadFormController) {
        counted.removeAll { $0.controller === controller }
        queued.removeAll { $0.controller === controller }
        promote()
    }

    /// A counted controller was released from memory, which frees its slot without a call.
    func slotMayHaveFreed() {
        promote()
    }

    private func prune() {
        counted.removeAll { $0.controller == nil }
        queued.removeAll { $0.controller == nil }
    }

    private func promote() {
        prune()
        while counted.count < limit, !queued.isEmpty {
            let next = queued.removeFirst()
            guard let controller = next.controller else { continue }
            counted.append(next)
            controller.startQueuedPrepare()
        }
    }
}
