import Foundation
#if canImport(OSLog)
    import OSLog
#endif

// MARK: - Public surface

/// Where the lead form is in its life. Carries only a state and, once submitted, the lead id and
/// when the form accepted it:
/// never the preparation token, a contact value, or an answer.
public enum LeadFormState: Equatable {
    case idle
    case preparing
    case prepared
    case activating
    case readyToShow
    case visible
    case submitting
    case submitted(leadId: String, submittedAt: Date)
    /// The form ended with `errorCode`. Decide whether to offer a retry from `retryable`, never from
    /// the code, and never show the code to the viewer. Codes the SDK itself reports:
    /// - `form_not_available`: Lead Generation is not available for this app right now (the form
    ///   page answered 404 or another 4xx, except 408 and 429). Not retryable: stop offering the
    ///   form on this ad.
    /// - `temporary_failure`: the form page could not be loaded (a 5xx server error, 429 rate
    ///   limited, 408 timeout, or no network).
    ///   Retryable: `retry()` loads it again.
    /// - `navigation_blocked`: the page tried to leave the form, so the SDK closed it.
    /// - `renderer_gone`: the page's web content process ended. Retryable before activation.
    /// - `reloaded`: the page reloaded after activation and lost what the viewer typed.
    /// - `bridge_error`: the page and the SDK could not talk (an unsupported bridge version).
    ///
    /// Any other code is the one the form reported, from the contract's error codes.
    case failed(errorCode: String, retryable: Bool)
    case expired
    case disposed
}

/// Why the form asks the app to open a web address.
public enum LeadFormLinkPurpose: String, Equatable, Sendable {
    /// The form's privacy policy, available any time the form is shown.
    case privacyPolicy = "privacy_policy"
    /// The advertiser's website, offered only after the form was submitted.
    case websiteCta = "website_cta"
}

/// Receives the controller's state changes and the form's requests. Held weakly.
@MainActor
public protocol LeadFormControllerDelegate: AnyObject {
    func leadFormController(_ controller: LeadFormController, didChange state: LeadFormState)
    func leadFormControllerDidRequestClose(_ controller: LeadFormController)
    /// The form asks the app to open `url` (always `https`). Open it outside the form, for example
    /// in an `SFSafariViewController`: the form and the answers typed so far stay as they are.
    /// Do not add the form's identifiers or any value to it.
    func leadFormController(_ controller: LeadFormController, openExternalURL url: URL, purpose: LeadFormLinkPurpose)
}

public extension LeadFormControllerDelegate {
    /// Ignores the request: the link is not opened.
    func leadFormController(_: LeadFormController, openExternalURL _: URL, purpose _: LeadFormLinkPurpose) {}
}

// MARK: - Transport seam

/// Why the form page could not be loaded.
enum LeadFormLoadFailure: Equatable {
    /// The page answered a 4xx other than 408 and 429 (`404 form_not_available` while Lead
    /// Generation is off): loading it again cannot help.
    case unavailable
    /// No answer, a 5xx, 408 or 429: loading it again may work.
    case transient
    /// The surface refused a main-frame navigation before any page committed (the launch address
    /// redirected): there is no form, and nothing would ever answer.
    case blocked
    /// The web content process ended.
    case rendererLost
}

/// What the controller needs from the surface that hosts the form page. Production is
/// ``SecureFormWebView``; unit tests drive the controller with a fake.
@MainActor
protocol LeadFormTransport: AnyObject {
    /// Receives each string the page posts, already filtered to the form's own frame and origin.
    var onMessage: ((String) -> Void)? { get set }
    /// The page could not be loaded, or its renderer was lost.
    var onLoadFailed: ((LeadFormLoadFailure) -> Void)? { get set }
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
    /// A retry of a never-opened form that is waiting for a hidden-form slot.
    private var retryQueued = false
    private var surfaceVisible = false
    /// What the page was last told: it has heard `became_visible` and not yet `became_hidden`.
    private var pageThinksVisible = false
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
        generation = optIn.snapshot().generation
        tracking = LeadFormTracking(send: fireTracking, retryDelaysMs: retryDelaysMs, logger: logger)
        channel = Self.mintChannel()
        transport.onMessage = { [weak self] text in self?.receive(text) }
        transport.onLoadFailed = { [weak self] in self?.loadFailed($0) }
        optIn.register(self, generation: generation)
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
        if retryQueued {
            retryQueued = false
            guard !isDisposed, case .failed(_, retryable: true) = state else {
                optIn.hiddenFormGate.release(self)
                return
            }
            guard !expireIfPastDeadline() else { return }
            performRetry()
            return
        }
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
            sendActivate()
        case .failed(_, retryable: true) where retryQueued:
            // The viewer tapped a form whose retry was waiting for a slot: an opened form needs none.
            retryQueued = false
            openRequested = true
            performRetry()
        default:
            break
        }
    }

    /// Tries again after a failure the form said is retryable.
    ///
    /// A form that was never opened is hidden prewarm like any other: when two other forms hold the
    /// hidden-form slots, the retry waits (the state stays `failed`) and proceeds when one frees.
    /// An opened form retries at once.
    public func retry() {
        guard !isDisposed, case .failed(_, retryable: true) = state else { return }
        if !openRequested, !optIn.hiddenFormGate.acquire(self) {
            retryQueued = true
            return
        }
        performRetry()
    }

    private func performRetry() {
        if retryIsReload {
            // No page was listening: load it again; its bridge_ready starts the exchange. Everything
            // tied to the old page goes, so the new one establishes its own readiness.
            retryIsReload = false
            guard !expireIfPastDeadline() else { return }
            resetPageScopedState()
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

    private func resetPageScopedState() {
        bridgeReadySeen = false
        exchanged = []
        context = LeadFormBridge.Context()
        requestedKeys = []
        activated = false
        retryIsActivation = false
        pageThinksVisible = false
    }

    /// Moves to `expired` when the descriptor's deadline has passed. Nothing is sent.
    @discardableResult
    private func expireIfPastDeadline() -> Bool {
        guard now() >= experience.expiresAt else { return false }
        set(.expired)
        return true
    }

    /// Hands the viewer's back press to the form. While the form is on screen (shown, submitting,
    /// or on its confirmation) the page does what its own Back arrow does: it goes back one stage
    /// with the answers kept, or asks to close on its first stage and on the confirmation, which
    /// reaches the delegate as a close request. While submitting the press is consumed and nothing
    /// is sent, since the page would ignore it.
    ///
    /// iOS has no system back button; call it from your own back control or gesture when you have
    /// one. It never closes the form by itself.
    ///
    /// - Returns: `true` when the form consumed the press; `false` when it belongs to the app (the
    ///   form is not on screen, has not been shown yet, failed, expired or was disposed, or the
    ///   message could not be sent).
    public func handleBack() -> Bool {
        guard !isDisposed, surfaceVisible, hasBeenVisible else { return false }
        switch state {
        case .submitting:
            return true
        case .visible, .submitted:
            return send(.back)
        default:
            return false
        }
    }

    /// Ends the form: tells the page when it is listening, releases the surface. Idempotent; after
    /// it every call and every incoming message is ignored and the delegate hears nothing more.
    public func dispose() {
        guard !isDisposed else { return }
        if bridgeReadySeen,
           let text = try? AppMessage.dispose.encode(
               instanceId: experience.formInstanceId,
               channel: channel,
               exchanged: exchanged
           )
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
        switch state {
        case .readyToShow:
            showIfReady()
        case .submitting:
            // The page keeps its state while submitting; it only needs to hear the change.
            guard hasBeenVisible, !pageThinksVisible else { return }
            pageThinksVisible = true
            send(.becameVisible)
        default:
            break
        }
    }

    func surfaceDidBecomeHidden() {
        guard !isDisposed else { return }
        surfaceVisible = false
        if state == .visible {
            set(.readyToShow)
        }
        guard pageThinksVisible, !isFinished else { return }
        pageThinksVisible = false
        send(.becameHidden)
    }

    /// The page hears `became_visible` first, then the delegate hears `visible`: a delegate that
    /// hides the surface from that callback produces a `became_hidden` the page can accept.
    private func showIfReady() {
        guard state == .readyToShow else { return }
        hasBeenVisible = true
        pageThinksVisible = true
        send(.becameVisible)
        guard state == .readyToShow else { return }
        set(.visible)
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
                set(.failed(errorCode: "bridge_error", retryable: false))
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

    /// The page failed to load, was blocked, or lost its renderer. Only the entry page counts: once
    /// the bridge is up, a load error is not the form failing to load. A lost renderer after
    /// activation is final (the answers typed so far are gone); before, loading again is safe.
    private func loadFailed(_ failure: LeadFormLoadFailure) {
        guard !isDisposed, !isFinished else { return }
        if failure == .rendererLost {
            if activated {
                set(.failed(errorCode: "renderer_gone", retryable: false))
            } else if [.preparing, .prepared, .activating].contains(state) {
                retryIsReload = true
                set(.failed(errorCode: "renderer_gone", retryable: true))
            } else if case .failed(_, retryable: true) = state {
                // A retryable failure from the page: its renderer is gone too, so retry must reload.
                retryIsReload = true
            }
            return
        }
        guard !bridgeReadySeen, [.preparing, .prepared, .activating].contains(state) else { return }
        switch failure {
        case .unavailable:
            // The page answered a 4xx (404 form_not_available) and will never send bridge_ready.
            set(.failed(errorCode: "form_not_available", retryable: false))
        case .blocked:
            set(.failed(errorCode: "navigation_blocked", retryable: false))
        case .transient, .rendererLost:
            retryIsReload = true
            set(.failed(errorCode: "temporary_failure", retryable: true))
        }
    }

    private var isFinished: Bool {
        switch state {
        case .failed(_, retryable: false), .expired, .disposed, .submitted: true
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
            // The delegate may itself have opened the form from the callback.
            if openRequested, state == .prepared {
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
            set(.failed(errorCode: code.rawValue, retryable: retryable && code.isRetryable && !activated))
        case let .fatalError(code):
            guard !isFinished else { return }
            set(code == .expired ? .expired : .failed(errorCode: code.rawValue, retryable: false))
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
        case let .submitted(leadId, submittedAt):
            guard state == .submitting else { return }
            set(.submitted(leadId: leadId, submittedAt: submittedAt))
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
                set(.failed(errorCode: "reloaded", retryable: false))
            }
            return
        default:
            return
        }
        if activated {
            set(.failed(errorCode: "reloaded", retryable: false))
            return
        }
        // Never hand the token to a form whose deadline passed while the page was loading.
        guard !expireIfPastDeadline() else { return }
        retryIsActivation = false
        set(.preparing)
        send(.initialize(preparationToken: experience.preparationToken, presentation: presentation))
    }

    // MARK: Outgoing

    private func sendActivate() {
        // A form is not activated with an authorization that has lapsed since it was prepared.
        guard !expireIfPastDeadline() else { return }
        set(.activating)
        send(.activate)
    }

    @discardableResult
    private func send(_ message: AppMessage) -> Bool {
        do {
            let text = try message.encode(
                instanceId: experience.formInstanceId,
                channel: channel,
                exchanged: exchanged,
                allowedPrefillKeys: requestedKeys
            )
            exchanged.insert(message.wireType)
            transport.send(text)
            return true
        } catch {
            let reason = (error as? BridgeRejection)?.description ?? "not encodable"
            logger
                .warning(
                    "Lead form bridge could not send \(message.wireType, privacy: .public): \(reason, privacy: .public)"
                )
            if !isFinished {
                set(.failed(errorCode: "bridge_error", retryable: false))
            }
            return false
        }
    }

    // MARK: Prefill

    /// Asks the app's provider for the requested values it holds, then sends `prefill` once.
    /// With nothing to ask, it is sent at once.
    private func startPrefill() {
        guard !prefillStarted else { return }
        prefillStarted = true
        let generation = generation
        let current = optIn.snapshot()
        guard current.generation == generation, let provider = current.provider else {
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
    func makeLeadFormController(
        for experience: LeadGenerationExperience,
        presentation: LeadFormPresentation
    ) -> LeadFormController? {
        guard interactiveExperienceBox.isEnabled else { return nil }
        // The id travels in the launch address and in every bridge message: one the contract would
        // refuse (or that could add a fragment parameter) gets no form at all.
        guard LeadFormBridge.isContractInstanceId(experience.formInstanceId) else {
            config.logger.warning("Lead form not created: the descriptor's formInstanceId is malformed")
            return nil
        }
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
