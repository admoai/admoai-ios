import Foundation
#if canImport(OSLog)
    import OSLog
#endif

// MARK: - Public surface

/// Where the lead form is in its life. Carries only a state and, once submitted, the lead id and
/// when the form accepted it:
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

/// Receives the controller's state changes and the form's request to be closed. Held weakly.
///
/// Experimental: import with `@_spi(InteractiveExperience) import AdMoai`.
@_spi(InteractiveExperience)
@MainActor
public protocol LeadFormControllerDelegate: AnyObject {
    func leadFormController(_ controller: LeadFormController, didChange state: LeadFormState)
    func leadFormControllerDidRequestClose(_ controller: LeadFormController)
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
/// form is no longer needed: the controller is not released by its owner alone being released
/// while a page is loading.
///
/// Links and form events the page requests are validated and ignored in this item: they are handled
/// in a later item. Contact values come from the provider in a later item: for now `prefill` is sent
/// with no values.
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

    private var exchanged = Set<String>()
    private var context = LeadFormBridge.Context()
    private var requestedKeys = Set<StandardAttributeKey>()
    private var activated = false
    private var bridgeReadySeen = false
    private var openRequested = false
    private var retryIsActivation = false
    private var retryIsReload = false
    private var surfaceVisible = false
    /// What the page was last told: it has heard `became_visible` and not yet `became_hidden`.
    private var pageThinksVisible = false
    private var hasBeenVisible = false
    private var isDisposed = false

    init(
        experience: LeadGenerationExperience,
        presentation: LeadFormPresentation,
        transport: LeadFormTransport,
        logger: Logger,
        now: @escaping () -> Date = Date.init
    ) {
        self.experience = experience
        self.presentation = presentation
        self.transport = transport
        self.logger = logger
        self.now = now
        channel = Self.mintChannel()
        transport.onMessage = { [weak self] text in self?.receive(text) }
        transport.onLoadFailed = { [weak self] in self?.loadFailed($0) }
    }

    // MARK: Commands

    /// Starts preparing the form in the background. Harmless when already started.
    public func prepare() {
        guard !isDisposed, state == .idle else { return }
        guard now() < experience.expiresAt else {
            set(.expired)
            return
        }
        set(.preparing)
        transport.load(launchURL())
    }

    /// The viewer tapped: activates the form, preparing it first when that has not happened yet
    /// (the same load is reused, never a second one).
    public func open() {
        guard !isDisposed else { return }
        switch state {
        case .idle:
            openRequested = true
            prepare()
        case .preparing:
            openRequested = true
            expireIfPastDeadline()
        case .prepared:
            openRequested = true
            sendActivate()
        default:
            break
        }
    }

    /// Tries again after a failure the form said is retryable.
    public func retry() {
        guard !isDisposed, case .failed(_, retryable: true) = state else { return }
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
            send(.prefill(values: [:]))
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
        case .requestExternalURL, .event:
            break
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

    private func send(_ message: AppMessage) {
        do {
            let text = try message.encode(
                instanceId: experience.formInstanceId,
                channel: channel,
                exchanged: exchanged,
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
                set(.failed(errorCode: "bridge_error", retryable: false))
            }
        }
    }

    private func set(_ newState: LeadFormState) {
        guard !isDisposed, newState != state else { return }
        state = newState
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
                logger: config.logger
            )
        #else
            return nil
        #endif
    }
}
