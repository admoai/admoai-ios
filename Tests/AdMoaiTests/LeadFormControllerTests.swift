@_spi(InteractiveExperience) @testable import AdMoai
import Foundation
import Testing
#if canImport(OSLog)
    import OSLog
#endif

/// The scenarios of `Sources/AdMoai/LeadFormController.feature`, one test per scenario. The
/// controller is driven through a fake transport: what the page would post comes in as bridge
/// messages, and what the SDK sends is recorded.
@MainActor
struct LeadFormControllerTests {
    private static let secret = "tok_SECRET_123"
    private static let instanceId = "form_instance_01KG000000000000000000N001"

    private final class FakeTransport: LeadFormTransport {
        var onMessage: ((String) -> Void)?
        var onLoadFailed: ((LeadFormLoadFailure) -> Void)?
        private(set) var loads: [URL] = []
        private(set) var sentTexts: [String] = []
        private(set) var teardowns = 0

        func load(_ url: URL) {
            loads.append(url)
        }

        func send(_ message: String) {
            sentTexts.append(message)
        }

        func teardown() {
            teardowns += 1
        }
    }

    private final class Clock {
        var date = Date()
    }

    private final class Recorder: LeadFormControllerDelegate {
        var states: [LeadFormState] = []
        var closeRequests = 0
        /// Runs inside the callback, the way an app's own delegate code would.
        var onChange: ((LeadFormState) -> Void)?

        func leadFormController(_: LeadFormController, didChange state: LeadFormState) {
            states.append(state)
            onChange?(state)
        }

        func leadFormControllerDidRequestClose(_: LeadFormController) {
            closeRequests += 1
        }
    }

    /// The `submittedAt` the tests' `submitted` messages carry (2026-11-12T15:04:05Z).
    private static let submittedAt = Date(timeIntervalSince1970: 1_794_495_845)

    /// Collects the tracking URLs the controller fires; the beacon always reports delivered.
    private final class Fired: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [URL] = []

        func add(_ url: URL) {
            lock.lock()
            items.append(url)
            lock.unlock()
        }

        var urls: [URL] {
            lock.lock()
            defer { lock.unlock() }
            return items
        }
    }

    /// Holds the given values; `delaysMs` makes a key answer late.
    private final class FakeProvider: LeadFormValueProvider {
        let values: [StandardAttributeKey: String?]
        let delaysMs: [StandardAttributeKey: Int]

        init(_ values: [StandardAttributeKey: String?], delaysMs: [StandardAttributeKey: Int] = [:]) {
            self.values = values
            self.delaysMs = delaysMs
        }

        var availableKeys: Set<StandardAttributeKey> {
            Set(values.keys)
        }

        func value(for key: StandardAttributeKey) async -> String? {
            if let delay = delaysMs[key] {
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            }
            return values[key] ?? nil
        }
    }

    /// Implements only what K2 conformers did: the link method is the default no-op.
    private final class StateOnlyDelegate: LeadFormControllerDelegate {
        func leadFormController(_: LeadFormController, didChange _: LeadFormState) {}
        func leadFormControllerDidRequestClose(_: LeadFormController) {}
    }

    private static func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0 ..< 400 where !condition() {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private final class LinkRecorder: LeadFormControllerDelegate {
        var links: [(url: URL, purpose: LeadFormLinkPurpose)] = []

        func leadFormController(_: LeadFormController, didChange _: LeadFormState) {}
        func leadFormControllerDidRequestClose(_: LeadFormController) {}
        func leadFormController(_: LeadFormController, openExternalURL url: URL, purpose: LeadFormLinkPurpose) {
            links.append((url, purpose))
        }
    }

    private static func experience(expiresIn: TimeInterval = 3600) -> LeadGenerationExperience {
        LeadGenerationExperience(
            formId: "form_1",
            preparedVersionId: "form_version_01KG000000000000000000V002",
            formInstanceId: instanceId,
            launchUrl: URL(string: "https://forms.example.invalid/launch?x=1")!,
            expiresAt: Date().addingTimeInterval(expiresIn),
            prefillAttributeKeys: [.email],
            preparationToken: secret
        )
    }

    private struct Sent: Equatable {
        let type: String
        let payload: [String: JSONValue]
    }

    @MainActor
    private final class Harness {
        let transport = FakeTransport()
        let recorder = Recorder()
        let controller: LeadFormController
        let clock = Clock()
        let box: InteractiveExperienceBox
        let fired = Fired()

        init(
            presentation: LeadFormPresentation = .fullScreen,
            expiresIn: TimeInterval = 3600,
            box: InteractiveExperienceBox = InteractiveExperienceBox(),
            provider: LeadFormValueProvider? = nil,
            prefillTimeoutMs: Int = LeadFormBridge.Limits.prefillLookupTimeoutMs,
            retryDelaysMs: [Int] = [5, 5]
        ) {
            self.box = box
            if let provider {
                box.set(provider)
            }
            let fired = fired
            let clock = clock
            let experience = LeadGenerationExperience(
                formId: "form_1",
                preparedVersionId: "form_version_01KG000000000000000000V002",
                formInstanceId: LeadFormControllerTests.instanceId,
                launchUrl: URL(string: "https://forms.example.invalid/launch?x=1")!,
                expiresAt: clock.date.addingTimeInterval(expiresIn),
                prefillAttributeKeys: [.email],
                preparationToken: LeadFormControllerTests.secret
            )
            controller = LeadFormController(
                experience: experience,
                presentation: presentation,
                transport: transport,
                logger: Logger(subsystem: "test", category: "LeadFormControllerTests"),
                now: { clock.date },
                optIn: box,
                prefillTimeoutMs: prefillTimeoutMs,
                fireTracking: { url, done in
                    fired.add(url)
                    done(true)
                },
                retryDelaysMs: retryDelaysMs
            )
            controller.delegate = recorder
        }

        var sent: [Sent] {
            transport.sentTexts.compactMap {
                guard let envelope = try? BridgeEnvelope.decode($0).get() else { return nil }
                return Sent(type: envelope.type, payload: envelope.payload)
            }
        }

        var sentTypes: [String] {
            sent.map(\.type)
        }

        /// What the page posts.
        func runtime(_ type: String, _ payload: [String: JSONValue] = [:], channel: String? = nil) {
            let text = try? BridgeEnvelope(
                type: type, instanceId: LeadFormControllerTests.instanceId,
                channel: channel ?? controller.channel, payload: payload
            ).encoded()
            transport.onMessage?(text ?? "")
        }

        func bridgeReady(version: String = "1") {
            runtime("bridge_ready", ["runtimeVersion": .string("1.0.0"), "bridgeVersion": .string(version)])
        }

        func prepared() {
            runtime("prepared", ["preparedVersionId": .string("form_version_01KG000000000000000000V002")])
        }

        func activated(keys: [String] = ["email"]) {
            let url = { (tag: String) in JSONValue.string("https://api.example.invalid/track?t=\(tag)") }
            runtime("activated", [
                "formVersionId": .string("form_version_01KG000000000000000000V003"),
                "requestedAttributeKeys": .array(keys.map { .string($0) }),
                "events": .array([
                    .object(["name": .string("form_open"), "url": url("a")]),
                    .object(["name": .string("form_start"), "url": url("b")]),
                ]),
            ])
        }

        var prefillValues: [String: JSONValue]? {
            guard case let .object(values)? = sent.first(where: { $0.type == "prefill" })?.payload["values"] else {
                return nil
            }
            return values
        }

        /// Prepare, tap, activate and show.
        func reachVisible() {
            controller.open()
            bridgeReady()
            prepared()
            activated()
            runtime("prefill_applied")
            controller.surfaceDidBecomeVisible()
        }
    }

    // Scenario 1
    @Test func theWholeHappyPath() throws {
        let h = Harness()
        h.reachVisible()
        #expect(h.sentTypes == ["initialize", "activate", "prefill", "became_visible"])
        #expect(h.recorder.states == [.preparing, .prepared, .activating, .readyToShow, .visible])
        let load = h.transport.loads.first
        #expect(load?.fragment == "instanceId=\(Self.instanceId)&channel=\(h.controller.channel)")
        #expect(load?.absoluteString.hasPrefix("https://forms.example.invalid/launch?x=1#") == true)
        let sent = h.sent
        try #require(sent.count == 4)
        #expect(sent[0].payload["preparationToken"] == .string(Self.secret))
        #expect(sent[2].payload == ["values": .object([:])])
        #expect(h.controller.channel.count == 32)
    }

    // Scenario 2
    @Test func aTapBeforeTheFormIsReadyReusesTheSameLoad() {
        let h = Harness()
        h.controller.open()
        #expect(h.controller.state == .preparing)
        h.controller.open()
        h.bridgeReady()
        #expect(h.sentTypes == ["initialize"])
        h.prepared()
        #expect(h.sentTypes == ["initialize", "activate"])
        #expect(h.controller.state == .activating)
        #expect(h.transport.loads.count == 1)
    }

    // Scenario 3
    @Test func preparingOrOpeningTwiceIsHarmless() {
        let h = Harness()
        h.controller.prepare()
        h.controller.prepare()
        h.controller.open()
        h.controller.open()
        h.bridgeReady()
        h.prepared()
        h.controller.open()
        h.controller.prepare()
        #expect(h.transport.loads.count == 1)
        #expect(h.sentTypes == ["initialize", "activate"])
    }

    // Scenario 4
    @Test func hidingAndShowingTellsTheFormOncePerChange() {
        let h = Harness()
        h.reachVisible()
        h.controller.surfaceDidBecomeHidden()
        h.controller.surfaceDidBecomeHidden()
        #expect(h.controller.state == .readyToShow)
        h.controller.surfaceDidBecomeVisible()
        h.controller.surfaceDidBecomeVisible()
        #expect(h.controller.state == .visible)
        #expect(h.sentTypes == [
            "initialize",
            "activate",
            "prefill",
            "became_visible",
            "became_hidden",
            "became_visible",
        ])
        #expect(h.sentTypes.filter { $0 == "activate" }.count == 1)
    }

    // Scenario 5
    @Test func anExpiredDescriptorNeverLoads() {
        let h = Harness(expiresIn: -1)
        h.controller.prepare()
        #expect(h.controller.state == .expired)
        h.controller.open()
        #expect(h.transport.loads.isEmpty)
        #expect(h.transport.sentTexts.isEmpty)
        #expect(h.recorder.states == [.expired])
    }

    // Scenario 6
    @Test func aRetryableFailureCanBeRetried() {
        let h = Harness()
        h.controller.prepare()
        h.bridgeReady()
        h.runtime("prepare_failed", ["errorCode": .string("temporary_failure"), "retryable": .bool(true)])
        #expect(h.controller.state == .failed(errorCode: "temporary_failure", retryable: true))
        h.controller.retry()
        #expect(h.controller.state == .preparing)
        #expect(h.sentTypes == ["initialize", "retry_prepare"])
        h.prepared()
        #expect(h.controller.state == .prepared)

        let fatal = Harness()
        fatal.controller.prepare()
        fatal.bridgeReady()
        fatal.runtime("prepare_failed", ["errorCode": .string("revoked"), "retryable": .bool(false)])
        fatal.controller.retry()
        #expect(fatal.controller.state == .failed(errorCode: "revoked", retryable: false))
        #expect(fatal.sentTypes == ["initialize"])
    }

    // Scenario 7
    @Test func aRetryableFailureWhileActivatingIsRetriedByActivatingAgain() {
        let h = Harness()
        h.controller.open()
        h.bridgeReady()
        h.prepared()
        h.runtime("prepare_failed", ["errorCode": .string("rate_limited"), "retryable": .bool(true)])
        #expect(h.controller.state == .failed(errorCode: "rate_limited", retryable: true))
        h.controller.retry()
        #expect(h.controller.state == .activating)
        #expect(h.sentTypes == ["initialize", "activate", "activate"])
    }

    // Scenario 8
    @Test func aFatalExpiryEndsTheForm() {
        let h = Harness()
        h.controller.prepare()
        h.bridgeReady()
        h.runtime("fatal_error", ["errorCode": .string("expired")])
        #expect(h.controller.state == .expired)
        let other = Harness()
        other.controller.prepare()
        other.bridgeReady()
        other.runtime("fatal_error", ["errorCode": .string("revoked")])
        #expect(other.controller.state == .failed(errorCode: "revoked", retryable: false))
    }

    // Scenario 9
    @Test func aPageThatSpeaksAnotherBridgeVersionIsUnavailable() {
        let h = Harness()
        h.controller.open()
        h.bridgeReady(version: "2")
        #expect(h.controller.state == .failed(errorCode: "bridge_error", retryable: false))
        #expect(h.sentTypes.isEmpty)
        #expect(!h.transport.sentTexts.contains { $0.contains(Self.secret) })
    }

    // Scenario 10
    @Test func aReloadedPageIsInitialisedAgainBeforeActivation() {
        let h = Harness()
        h.controller.open()
        h.bridgeReady()
        h.prepared()
        h.bridgeReady()
        #expect(h.controller.state == .preparing)
        h.prepared()
        h.activated()
        h.runtime("prefill_applied")
        #expect(h.controller.state == .readyToShow)
        #expect(h.sentTypes == ["initialize", "activate", "initialize", "activate", "prefill"])
    }

    // Scenario 11
    @Test func aReloadAfterActivationFailsWithoutARetry() {
        let h = Harness()
        h.controller.open()
        h.bridgeReady()
        h.prepared()
        h.activated()
        h.bridgeReady()
        #expect(h.controller.state == .failed(errorCode: "reloaded", retryable: false))
        h.controller.retry()
        #expect(h.sentTypes == ["initialize", "activate", "prefill"])
    }

    // Scenario 12
    @Test func aFailedSubmissionReturnsToVisible() {
        let h = Harness()
        h.reachVisible()
        h.runtime("submitting")
        #expect(h.controller.state == .submitting)
        h.runtime("submit_failed", ["errorCode": .string("temporary_failure"), "retryable": .bool(true)])
        #expect(h.controller.state == .visible)
        h.runtime("submitting")
        h.runtime(
            "submitted",
            ["leadId": .string("lead_01KG000000000000000000W001"), "submittedAt": .string("2026-11-12T15:04:05Z")]
        )
        #expect(h.controller.state == .submitted(
            leadId: "lead_01KG000000000000000000W001",
            submittedAt: Self.submittedAt
        ))

        // An answer with no unanswered submitting before it is refused.
        let again = Harness()
        again.reachVisible()
        again.runtime("submitting")
        again.runtime("submit_failed", ["errorCode": .string("unauthorized"), "retryable": .bool(false)])
        #expect(again.controller.state == .visible)
        again.runtime(
            "submitted",
            ["leadId": .string("lead_01KG000000000000000000W001"), "submittedAt": .string("2026-11-12T15:04:05Z")]
        )
        #expect(again.controller.state == .visible, "submitted after submit_failed needs a new submitting")
        again.runtime("submit_failed", ["errorCode": .string("temporary_failure"), "retryable": .bool(true)])
        #expect(!again.recorder.states.contains(.submitted(
            leadId: "lead_01KG000000000000000000W001",
            submittedAt: Self.submittedAt
        )))
    }

    // Scenario 13
    @Test func aSubmissionReportsOnlyItsLeadId() {
        let h = Harness()
        h.reachVisible()
        h.runtime(
            "submitted",
            ["leadId": .string("lead_01KG000000000000000000W001"), "submittedAt": .string("2026-11-12T15:04:05Z")]
        )
        // `submitted` must follow `submitting`: out of order, refused, nothing changes.
        #expect(h.controller.state == .visible)
        h.runtime("submitting")
        h.runtime(
            "submitted",
            ["leadId": .string("lead_01KG000000000000000000W001"), "submittedAt": .string("2026-11-12T15:04:05Z")]
        )
        #expect(h.recorder.states.last == .submitted(
            leadId: "lead_01KG000000000000000000W001",
            submittedAt: Self.submittedAt
        ))
    }

    // Scenario 14
    @Test func disposingIsFinal() {
        let h = Harness()
        h.controller.open()
        h.bridgeReady()
        h.controller.dispose()
        h.controller.dispose()
        #expect(h.sentTypes == ["initialize", "dispose"])
        #expect(h.transport.teardowns == 1)
        #expect(h.controller.state == .disposed)
        let callbacks = h.recorder.states.count
        h.prepared()
        h.runtime("request_close")
        h.controller.open()
        h.controller.prepare()
        h.controller.surfaceDidBecomeVisible()
        #expect(h.recorder.states.count == callbacks)
        #expect(h.recorder.closeRequests == 0)
        #expect(h.sentTypes == ["initialize", "dispose"])

        let early = Harness()
        early.controller.dispose()
        #expect(early.sentTypes.isEmpty, "nothing to tell a page that never spoke")
    }

    // Scenario 15
    @Test func theFormCanAskToBeClosed() {
        let h = Harness()
        h.controller.prepare()
        h.bridgeReady()
        h.runtime("request_close")
        #expect(h.recorder.closeRequests == 1)
    }

    // Scenario 16
    @Test func bothPresentationsReachTheForm() {
        for (presentation, wire) in [(LeadFormPresentation.inline, "inline"), (.fullScreen, "full_screen")] {
            let h = Harness(presentation: presentation)
            h.controller.prepare()
            h.bridgeReady()
            #expect(h.sent.first?.payload["presentation"] == .string(wire))
        }
    }

    // Scenario 17
    @Test func aRefusedMessageChangesNothing() {
        let h = Harness()
        h.controller.prepare()
        h.bridgeReady()
        let before = (h.controller.state, h.transport.sentTexts, h.recorder.states)
        h.prepared() // fine
        h.runtime("prepared", ["preparedVersionId": .string("nope")]) // bad payload
        h.runtime("submitted", [:], channel: "chan_example_0000000002") // wrong channel
        h.transport.onMessage?("not json")
        #expect(h.controller.state == .prepared)
        #expect(h.transport.sentTexts == before.1)
        #expect(h.recorder.states == before.2 + [.prepared])
    }

    // Scenario 18
    @Test func nothingTheAppHearsHoldsTheTokenOrAValue() {
        let h = Harness()
        h.reachVisible()
        h.runtime("submitting")
        h.runtime(
            "submitted",
            ["leadId": .string("lead_01KG000000000000000000W001"), "submittedAt": .string("2026-11-12T15:04:05Z")]
        )
        #expect(h.recorder.states.count >= 6)
        for state in h.recorder.states {
            var dumped = ""
            dump(state, to: &dumped)
            for output in [String(describing: state), String(reflecting: state), dumped] {
                #expect(!output.contains(Self.secret))
            }
        }
    }

    // Scenario 19
    @Test func aTapAfterTheDeadlineNeverActivates() {
        let prepared = Harness(expiresIn: 60)
        prepared.controller.prepare()
        prepared.bridgeReady()
        prepared.prepared()
        prepared.clock.date += 120
        prepared.controller.open()
        #expect(prepared.controller.state == .expired)
        #expect(prepared.sentTypes == ["initialize"])

        let preparing = Harness(expiresIn: 60)
        preparing.controller.prepare()
        preparing.bridgeReady()
        preparing.clock.date += 120
        preparing.controller.open()
        #expect(preparing.controller.state == .expired)
        preparing.prepared()
        #expect(preparing.sentTypes == ["initialize"])

        let fresh = Harness(expiresIn: 60)
        fresh.controller.prepare()
        fresh.bridgeReady()
        fresh.prepared()
        fresh.clock.date += 30
        fresh.controller.open()
        #expect(fresh.controller.state == .activating)
    }

    // Scenario 20
    @Test func prepareFailureCodesDecideWhetherARetryCanHelp() {
        let cases: [(code: String, flag: Bool, state: LeadFormState)] = [
            ("expired", true, .expired),
            ("revoked", true, .failed(errorCode: "revoked", retryable: false)),
            ("form_not_available", true, .failed(errorCode: "form_not_available", retryable: false)),
            ("unauthorized", true, .failed(errorCode: "unauthorized", retryable: false)),
            ("rate_limited", true, .failed(errorCode: "rate_limited", retryable: true)),
            ("temporary_failure", true, .failed(errorCode: "temporary_failure", retryable: true)),
            ("temporary_failure", false, .failed(errorCode: "temporary_failure", retryable: false)),
        ]
        for item in cases {
            let h = Harness()
            h.controller.prepare()
            h.bridgeReady()
            h.runtime("prepare_failed", ["errorCode": .string(item.code), "retryable": .bool(item.flag)])
            #expect(h.controller.state == item.state, "\(item.code) retryable \(item.flag)")
        }
    }

    // Scenario 21
    @Test func aPageThatCannotLoadIsReloadedOnRetry() {
        let offline = Harness()
        offline.controller.prepare()
        offline.transport.onLoadFailed?(.transient)
        #expect(offline.controller.state == .failed(errorCode: "temporary_failure", retryable: true))
        offline.controller.retry()
        #expect(offline.controller.state == .preparing)
        #expect(offline.transport.loads.count == 2)
        #expect(offline.transport.loads[0] == offline.transport.loads[1])
        offline.bridgeReady()
        offline.prepared()
        #expect(offline.sentTypes == ["initialize"])
        #expect(offline.controller.state == .prepared)
        offline.controller.retry()
        #expect(offline.transport.loads.count == 2)

        let lost = Harness()
        lost.controller.prepare()
        lost.bridgeReady()
        lost.transport.onLoadFailed?(.transient)
        #expect(lost.controller.state == .preparing, "after bridge_ready a load error is not the page failing")
        lost.transport.onLoadFailed?(.rendererLost)
        #expect(lost.controller.state == .failed(errorCode: "renderer_gone", retryable: true))
        lost.controller.retry()
        #expect(lost.transport.loads.count == 2)
        #expect(!lost.sentTypes.contains("retry_prepare"))
        lost.bridgeReady()
        #expect(lost.sentTypes == ["initialize", "initialize"])
    }

    // Scenario 22
    @Test func losingTheRendererAfterActivationIsFinal() {
        let h = Harness()
        h.controller.open()
        h.bridgeReady()
        h.prepared()
        h.activated()
        h.transport.onLoadFailed?(.rendererLost)
        #expect(h.controller.state == .failed(errorCode: "renderer_gone", retryable: false))
        h.controller.retry()
        #expect(h.transport.loads.count == 1)
        #expect(h.controller.state == .failed(errorCode: "renderer_gone", retryable: false))
    }

    // Scenario 23
    @Test func anAppThatDidNotOptInGetsNoController() {
        let config = SDKConfig(baseUrl: "https://api.mock.admoai.com", apiVersion: "2025-11-01")
        let sdk = AdMoai(config: config)
        let experience = LeadGenerationExperience(
            formId: "f", preparedVersionId: "v", formInstanceId: Self.instanceId,
            launchUrl: URL(string: "https://forms.example.invalid/")!, expiresAt: Date().addingTimeInterval(60),
            prefillAttributeKeys: [], preparationToken: Self.secret
        )
        #expect(sdk.makeLeadFormController(for: experience, presentation: .inline) == nil)

        // Opted in on a platform that can show it: a controller; the macOS host needs the override.
        final class Provider: LeadFormValueProvider { var availableKeys: Set<StandardAttributeKey> {
            []
        } }
        let provider = Provider()
        sdk.enableInteractiveExperiences(valueProvider: provider)
        sdk.interactiveExperienceBox.platformSupportsSecureFormView = false
        #expect(
            sdk.makeLeadFormController(for: experience, presentation: .inline) == nil,
            "no secure view on this host"
        )
        sdk.interactiveExperienceBox.platformSupportsSecureFormView = true
        let controller = sdk.makeLeadFormController(for: experience, presentation: .inline)
        #expect(controller != nil)
        controller?.dispose()

        // A descriptor whose instance id the contract would refuse gets no controller.
        for bad in [
            "",
            "form_instance_x&channel=evil",
            Self.instanceId + "\n",
            "FORM_INSTANCE_01KG000000000000000000N001",
        ] {
            let malformed = LeadGenerationExperience(
                formId: "f", preparedVersionId: "v", formInstanceId: bad,
                launchUrl: URL(string: "https://forms.example.invalid/")!, expiresAt: Date().addingTimeInterval(60),
                prefillAttributeKeys: [], preparationToken: Self.secret
            )
            #expect(sdk.makeLeadFormController(for: malformed, presentation: .inline) == nil, "\(bad)")
        }
    }

    // Scenario 24
    @Test func aFormThePageServerRefusesEndsAtOnce() {
        let h = Harness()
        h.controller.open()
        h.transport.onLoadFailed?(.unavailable) // 404 form_not_available, Lead Generation off
        #expect(h.controller.state == .failed(errorCode: "form_not_available", retryable: false))
        h.controller.retry()
        #expect(h.transport.loads.count == 1, "nothing to reload: the server does not serve the form")
        #expect(h.sentTypes.isEmpty)

        // The launch address redirected: the surface refused it before any page committed.
        let blocked = Harness()
        blocked.controller.open()
        blocked.transport.onLoadFailed?(.blocked)
        #expect(blocked.controller.state == .failed(errorCode: "navigation_blocked", retryable: false))
    }

    // Scenario 25
    @Test func aReloadStartsFromACleanPage() {
        let h = Harness()
        h.controller.prepare()
        h.bridgeReady()
        h.transport.onLoadFailed?(.rendererLost)
        #expect(h.controller.state == .failed(errorCode: "renderer_gone", retryable: true))
        h.controller.retry()
        #expect(h.controller.state == .preparing)
        #expect(h.transport.loads.count == 2)
        // The new page never spoke, so a load failure on it is the form failing to load, not noise.
        h.transport.onLoadFailed?(.transient)
        #expect(h.controller.state == .failed(errorCode: "temporary_failure", retryable: true))
    }

    // Scenario 26
    @Test func hidingAndShowingWhileSubmittingTellsTheFormWithoutLeavingSubmitting() {
        let h = Harness()
        h.reachVisible()
        h.runtime("submitting")
        h.controller.surfaceDidBecomeHidden()
        #expect(h.controller.state == .submitting)
        h.controller.surfaceDidBecomeHidden()
        h.controller.surfaceDidBecomeVisible()
        h.controller.surfaceDidBecomeVisible()
        #expect(h.controller.state == .submitting)
        #expect(h.sentTypes.suffix(3) == ["became_visible", "became_hidden", "became_visible"][...])
        h.runtime(
            "submitted",
            ["leadId": .string("lead_01KG000000000000000000W001"), "submittedAt": .string("2026-11-12T15:04:05Z")]
        )
        #expect(h.controller.state == .submitted(
            leadId: "lead_01KG000000000000000000W001",
            submittedAt: Self.submittedAt
        ))
    }

    // Scenario 27
    @Test func aDelegateThatHidesTheSurfaceFromTheVisibleCallbackDoesNotBreakTheBridge() {
        let h = Harness()
        let controller = h.controller
        h.recorder.onChange = {
            if $0 == .visible {
                controller.surfaceDidBecomeHidden()
            }
        }
        h.reachVisible()
        #expect(h.controller.state == .readyToShow)
        #expect(h.sentTypes == ["initialize", "activate", "prefill", "became_visible", "became_hidden"])
        #expect(!h.recorder.states.contains(.failed(errorCode: "bridge_error", retryable: false)))
    }

    // Scenario 28
    @Test func aRendererLostDuringARetryableFailureIsReloadedOnRetry() {
        let h = Harness()
        h.controller.prepare()
        h.bridgeReady()
        h.runtime("prepare_failed", ["errorCode": .string("temporary_failure"), "retryable": .bool(true)])
        h.transport.onLoadFailed?(.rendererLost)
        #expect(h.controller.state == .failed(errorCode: "temporary_failure", retryable: true))
        h.controller.retry()
        #expect(h.controller.state == .preparing)
        #expect(h.transport.loads.count == 2)
        #expect(!h.sentTypes.contains("retry_prepare"))
    }

    // Scenario 29
    @Test func aDelegateThatOpensFromThePreparedCallbackActivatesOnce() {
        let h = Harness()
        let controller = h.controller
        h.controller.open()
        h.bridgeReady()
        h.recorder.onChange = {
            if $0 == .prepared {
                controller.open()
            }
        }
        h.prepared()
        #expect(h.controller.state == .activating)
        #expect(h.sentTypes == ["initialize", "activate"])
    }

    // Scenario 30
    @Test func aFailureAfterActivationOffersNoActivationRetry() {
        let h = Harness()
        h.controller.open()
        h.bridgeReady()
        h.prepared()
        h.activated()
        h.runtime("prepare_failed", ["errorCode": .string("rate_limited"), "retryable": .bool(true)])
        #expect(h.controller.state == .failed(errorCode: "rate_limited", retryable: false))
        h.controller.retry()
        #expect(h.sentTypes == ["initialize", "activate", "prefill"])
    }

    // Scenario 31
    @Test func aPageThatSpeaksAfterTheDeadlineIsNeverSentTheToken() {
        let h = Harness(expiresIn: 60)
        h.controller.prepare()
        h.clock.date += 120
        h.bridgeReady()
        #expect(h.controller.state == .expired)
        #expect(h.transport.sentTexts.isEmpty)
        #expect(!h.transport.sentTexts.contains { $0.contains(Self.secret) })
    }

    // Scenario 32
    @Test func anActivationAfterTheDeadlineNeverActivates() {
        // A tap made while preparing, answered after the deadline.
        let pending = Harness(expiresIn: 60)
        pending.controller.open()
        pending.bridgeReady()
        pending.clock.date += 120
        pending.prepared()
        #expect(pending.controller.state == .expired)
        #expect(pending.sentTypes == ["initialize"])

        // An activation retry after the deadline.
        let retried = Harness(expiresIn: 60)
        retried.controller.open()
        retried.bridgeReady()
        retried.prepared()
        retried.runtime("prepare_failed", ["errorCode": .string("rate_limited"), "retryable": .bool(true)])
        #expect(retried.controller.state == .failed(errorCode: "rate_limited", retryable: true))
        retried.clock.date += 120
        retried.controller.retry()
        #expect(retried.controller.state == .expired)
        #expect(retried.sentTypes == ["initialize", "activate"])
    }

    // Scenario 33
    @Test func theFormReceivesTheValuesTheAppHoldsForTheKeysItRequested() async {
        let provider = FakeProvider([.email: "  ana@example.invalid ", .phone: "+34123", .gender: "other"])
        let h = Harness(provider: provider)
        h.controller.open()
        h.bridgeReady()
        h.prepared()
        h.activated(keys: ["email", "gender"])
        await Self.waitUntil { h.prefillValues != nil }
        #expect(h.sentTypes == ["initialize", "activate", "prefill"])
        #expect(h.prefillValues == ["email": .string("ana@example.invalid"), "gender": .string("other")])
        h.runtime("prefill_applied")
        #expect(h.controller.state == .readyToShow)
        #expect(h.recorder.states == [.preparing, .prepared, .activating, .readyToShow])
    }

    // Scenario 34
    @Test func valuesThatAreBlankTooLongOrNotAGenderOptionAreNotSent() async {
        let provider = FakeProvider([
            .firstName: "   ", .lastName: String(repeating: "x", count: 257), .email: "a@b.co",
            .gender: "unicorn", .phone: nil,
        ])
        let h = Harness(provider: provider)
        h.controller.open()
        h.bridgeReady()
        h.prepared()
        h.activated(keys: ["firstName", "lastName", "email", "gender", "phone"])
        await Self.waitUntil { h.prefillValues != nil }
        #expect(h.prefillValues == ["email": .string("a@b.co")])
    }

    // Scenario 35
    @Test func aValueThatArrivesAfterTheDeadlineIsNeverSent() async {
        let provider = FakeProvider(
            [.email: "fast@example.invalid", .phone: "+34123"], delaysMs: [.phone: 300]
        )
        let h = Harness(provider: provider, prefillTimeoutMs: 40)
        h.controller.open()
        h.bridgeReady()
        h.prepared()
        h.activated(keys: ["email", "phone"])
        await Self.waitUntil { h.prefillValues != nil }
        #expect(h.prefillValues == ["email": .string("fast@example.invalid")])
        try? await Task.sleep(nanoseconds: 400_000_000)
        #expect(h.sentTypes.filter { $0 == "prefill" }.count == 1)
    }

    // Scenario 36
    @Test func withNothingToAskPrefillIsSentAtOnceAndEmpty() {
        let provider = FakeProvider([.phone: "+34123"])
        let h = Harness(provider: provider)
        h.controller.open()
        h.bridgeReady()
        h.prepared()
        h.activated(keys: ["email"])
        #expect(h.sentTypes == ["initialize", "activate", "prefill"])
        #expect(h.prefillValues == [:])
    }

    // Scenario 37
    @Test func aUserChangeDuringALookupDisposesTheFormAndDropsTheValue() async {
        let provider = FakeProvider([.email: "userA@example.invalid"], delaysMs: [.email: 80])
        let h = Harness(provider: provider)
        h.controller.open()
        h.bridgeReady()
        h.prepared()
        h.activated()
        h.box.userDidChange()
        await Self.waitUntil { h.controller.state == .disposed }
        #expect(h.controller.state == .disposed)
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(h.sentTypes == ["initialize", "activate", "dispose"])
        #expect(!h.transport.sentTexts.contains { $0.contains("userA") })
        #expect(h.transport.teardowns == 1)
    }

    // Scenario 38
    @Test func changingTheProviderOrDisablingDisposesEveryFormButTheSameProviderDoesNot() async {
        let sdk = AdMoai(config: SDKConfig(baseUrl: "https://api.mock.admoai.com", apiVersion: "2025-11-01"))
        let first = FakeProvider([:])
        sdk.enableInteractiveExperiences(valueProvider: first)
        let a = Harness(box: sdk.interactiveExperienceBox)
        let b = Harness(box: sdk.interactiveExperienceBox)
        sdk.enableInteractiveExperiences(valueProvider: first)
        await Task.yield()
        #expect(a.controller.state == .idle)

        sdk.enableInteractiveExperiences(valueProvider: FakeProvider([:]))
        await Self.waitUntil { a.controller.state == .disposed && b.controller.state == .disposed }
        #expect(a.controller.state == .disposed)
        #expect(b.controller.state == .disposed)

        let c = Harness(box: sdk.interactiveExperienceBox)
        sdk.disableInteractiveExperiences()
        await Self.waitUntil { c.controller.state == .disposed }
        #expect(c.controller.state == .disposed)
    }

    // Scenario 38
    @Test func switchingOrClearingTheUserDisposesFormsButANewConsentOrSameIdDoesNot() async {
        var sdk = AdMoai(config: SDKConfig(baseUrl: "https://api.mock.admoai.com", apiVersion: "2025-11-01"))
        sdk.setUserConfig(id: "user-a")
        let box = sdk.interactiveExperienceBox
        let h = Harness(box: box)
        sdk.setUserConfig(id: "user-a", timezone: "Europe/Madrid")
        sdk.setUserConfig(timezone: "Europe/Paris")
        await Task.yield()
        #expect(h.controller.state == .idle)

        sdk.setUserConfig(id: "user-b")
        await Self.waitUntil { h.controller.state == .disposed }
        #expect(h.controller.state == .disposed)

        let other = Harness(box: box)
        sdk.clearUserConfig()
        await Self.waitUntil { other.controller.state == .disposed }
        #expect(other.controller.state == .disposed)
    }

    // Scenario 39
    @Test func theFormAsksTheAppToOpenItsLinksOutsideTheForm() {
        let h = Harness()
        let delegate = LinkRecorder()
        h.controller.delegate = delegate
        h.reachVisible()
        h.runtime(
            "request_external_url",
            ["purpose": .string("privacy_policy"), "url": .string("https://example.invalid/privacy")]
        )
        // Before the form was submitted, the website is refused and the delegate hears nothing.
        h.runtime(
            "request_external_url",
            ["purpose": .string("website_cta"), "url": .string("https://example.invalid/site")]
        )
        h.runtime(
            "request_external_url",
            ["purpose": .string("privacy_policy"), "url": .string("http://example.invalid/privacy")]
        )
        #expect(delegate.links.map(\.purpose) == [.privacyPolicy])
        #expect(delegate.links.first?.url.absoluteString == "https://example.invalid/privacy")
        h.runtime("submitting")
        h.runtime(
            "submitted",
            ["leadId": .string("lead_01KG000000000000000000W001"), "submittedAt": .string("2026-11-12T15:04:05Z")]
        )
        h.runtime(
            "request_external_url",
            ["purpose": .string("website_cta"), "url": .string("https://example.invalid/site")]
        )
        #expect(delegate.links.map(\.purpose) == [.privacyPolicy, .websiteCta])
        #expect(h.controller.state == .submitted(
            leadId: "lead_01KG000000000000000000W001",
            submittedAt: Self.submittedAt
        ))

        // A delegate written before links existed still compiles and ignores them.
        let old = Harness()
        let stateOnly = StateOnlyDelegate()
        old.controller.delegate = stateOnly
        old.reachVisible()
        old.runtime(
            "request_external_url",
            ["purpose": .string("privacy_policy"), "url": .string("https://example.invalid/privacy")]
        )
        #expect(old.controller.state == .visible)
    }

    // Scenario 40
    @Test func aFormEventFiresItsActivationUrlOncePerForm() async {
        let h = Harness()
        h.reachVisible()
        #expect(h.fired.urls.isEmpty, "preparing, activating and prefill fire nothing")
        h.runtime("event", ["name": .string("form_open")])
        await Self.waitUntil { h.fired.urls.count == 1 }
        #expect(h.fired.urls.map(\.absoluteString) == ["https://api.example.invalid/track?t=a"])
        h.controller.surfaceDidBecomeHidden()
        h.controller.surfaceDidBecomeVisible()
        h.runtime("event", ["name": .string("form_open")])
        h.runtime("event", ["name": .string("form_start")])
        await Self.waitUntil { h.fired.urls.count == 2 }
        #expect(h.fired.urls.map(\.absoluteString) == [
            "https://api.example.invalid/track?t=a", "https://api.example.invalid/track?t=b",
        ])
        // The page names events only: one that activation did not list is refused, fires nothing.
        h.runtime("event", ["name": .string("website_cta_click")])
        h.runtime("event", ["name": .string("form_open"), "url": .string("https://evil.invalid/x")])
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(h.fired.urls.count == 2)
    }

    // Scenario 41
    @Test func atMostTwoHiddenFormsPrepareAndTheRestWaitForASlot() {
        let box = InteractiveExperienceBox()
        let first = Harness(box: box)
        let second = Harness(box: box)
        let third = Harness(box: box)
        let fourth = Harness(box: box)
        for h in [first, second, third, fourth] {
            h.controller.prepare()
        }
        #expect(first.controller.state == .preparing)
        #expect(second.controller.state == .preparing)
        #expect(third.controller.state == .idle)
        #expect(third.transport.loads.isEmpty)
        third.controller.prepare()
        #expect(third.transport.loads.isEmpty)

        // Opening one frees its slot: the next in line starts, in order.
        first.controller.open()
        #expect(third.controller.state == .preparing)
        #expect(third.transport.loads.count == 1)
        #expect(fourth.controller.state == .idle)

        // Disposing frees one too.
        second.controller.dispose()
        #expect(fourth.controller.state == .preparing)

        // A failure frees one.
        let fifth = Harness(box: box)
        fifth.controller.prepare()
        #expect(fifth.controller.state == .idle)
        third.transport.onLoadFailed?(.transient)
        #expect(third.controller.state == .failed(errorCode: "temporary_failure", retryable: true))
        #expect(fifth.controller.state == .preparing)
    }

    // Scenario 42
    @Test func openingAWaitingFormAlwaysProceedsAndLeavesTheQueue() {
        let box = InteractiveExperienceBox()
        let a = Harness(box: box)
        let b = Harness(box: box)
        let waiting = Harness(box: box)
        let behind = Harness(box: box)
        for h in [a, b, waiting, behind] {
            h.controller.prepare()
        }
        waiting.controller.open()
        #expect(waiting.controller.state == .preparing)
        #expect(waiting.transport.loads.count == 1)
        // Leaving the queue freed no slot: the form behind it still waits.
        #expect(behind.controller.state == .idle)
        a.controller.dispose()
        #expect(behind.controller.state == .preparing)
        #expect(waiting.transport.loads.count == 1)

        // A form never prepared in the background is opened directly, whatever the bound.
        let direct = Harness(box: box)
        direct.controller.open()
        #expect(direct.controller.state == .preparing)
    }

    // Scenario 43
    @Test func aWaitingFormThatExpiredNeverLoads() {
        let box = InteractiveExperienceBox()
        let a = Harness(box: box)
        let b = Harness(box: box)
        let late = Harness(expiresIn: 60, box: box)
        for h in [a, b, late] {
            h.controller.prepare()
        }
        late.clock.date += 120
        a.controller.dispose()
        #expect(late.controller.state == .expired)
        #expect(late.transport.loads.isEmpty)
    }

    // Scenario 44
    @Test func releasingAControllerTearsItsPageDownAndFreesItsSlot() async {
        let box = InteractiveExperienceBox()
        let waiting = Harness(box: box)
        let transport = FakeTransport()
        let other = Harness(box: box)
        var held: LeadFormController? = LeadFormController(
            experience: Self.experience(),
            presentation: .inline,
            transport: transport,
            logger: Logger(subsystem: "test", category: "LeadFormControllerTests"),
            optIn: box
        )
        weak var released = held
        held?.prepare()
        #expect(transport.loads.count == 1)
        other.controller.prepare()
        waiting.controller.prepare()
        #expect(waiting.controller.state == .idle)
        held = nil
        await Self.waitUntil { released == nil && transport.teardowns == 1 }
        #expect(released == nil)
        #expect(transport.teardowns == 1)
        await Self.waitUntil { waiting.controller.state == .preparing }
        #expect(waiting.controller.state == .preparing)
    }

    // Scenario 45
    @Test func theBackPressGoesToTheFormOnlyWhileItIsOnScreen() {
        let h = Harness()
        #expect(h.controller.handleBack() == false, "nothing shown yet")
        h.controller.open()
        h.bridgeReady()
        h.prepared()
        h.activated()
        h.runtime("prefill_applied")
        #expect(h.controller.handleBack() == false, "ready but not on screen")
        h.controller.surfaceDidBecomeVisible()
        #expect(h.controller.handleBack() == true)
        #expect(h.sent.last == Sent(type: "back", payload: [:]))
        h.runtime("request_close")
        #expect(h.recorder.closeRequests == 1, "the page's answer on its first stage reaches the delegate")
        #expect(h.controller.state == .visible, "back never closes the form by itself")

        h.controller.surfaceDidBecomeHidden()
        let sentWhileHidden = h.sentTypes.count
        #expect(h.controller.handleBack() == false, "hidden: the press belongs to the app")
        #expect(h.sentTypes.count == sentWhileHidden)

        h.controller.surfaceDidBecomeVisible()
        h.runtime("submitting")
        let sentBeforeSubmitBack = h.sentTypes.count
        #expect(h.controller.handleBack() == true, "consumed while submitting")
        #expect(h.sentTypes.count == sentBeforeSubmitBack, "nothing is sent mid-submit; the page would ignore it")
        h.runtime(
            "submitted",
            ["leadId": .string("lead_01KG000000000000000000W001"), "submittedAt": .string("2026-11-12T15:04:05Z")]
        )
        #expect(h.controller.handleBack() == true, "on the confirmation the page answers request_close")
        #expect(h.sentTypes.filter { $0 == "back" }.count == 2)

        h.controller.dispose()
        #expect(h.controller.handleBack() == false)
    }

    // Scenario 45
    @Test func aFailedFormLeavesTheBackPressToTheApp() {
        let h = Harness()
        h.reachVisible()
        h.bridgeReady() // the page reloaded after activation: the answers are gone
        #expect(h.controller.state == .failed(errorCode: "reloaded", retryable: false))
        #expect(h.controller.handleBack() == false)
        #expect(!h.sentTypes.contains("back"))
    }

    // Scenario 46
    @Test func aFormCreatedForAnOptInThatChangedBeforeRegisteringIsDisposed() async {
        let box = InteractiveExperienceBox()
        let captured = box.snapshot().generation
        box.userDidChange()
        let stale = Harness(box: box)
        box.register(stale.controller, generation: captured)
        #expect(stale.controller.state == .disposed)
        stale.controller.prepare()
        stale.controller.open()
        #expect(stale.transport.loads.isEmpty)

        let current = Harness(box: box)
        current.controller.prepare()
        #expect(current.controller.state == .preparing)
        box.userDidChange()
        await Self.waitUntil { current.controller.state == .disposed }
        #expect(current.controller.state == .disposed, "a registration for the current opt-in still succeeds")
    }

    // Scenario 47
    @Test func retryingAFormThatWasNeverOpenedWaitsForAHiddenFormSlot() {
        let failedPrepare = ["errorCode": JSONValue.string("temporary_failure"), "retryable": .bool(true)]

        // A page that could not load is reloaded once a slot frees.
        let reloadBox = InteractiveExperienceBox()
        let a = Harness(box: reloadBox)
        let b = Harness(box: reloadBox)
        let c = Harness(box: reloadBox)
        for h in [a, b, c] {
            h.controller.prepare()
        }
        #expect(c.controller.state == .idle)
        a.transport.onLoadFailed?(.transient)
        #expect(c.controller.state == .preparing)
        a.controller.retry()
        #expect(a.controller.state == .failed(errorCode: "temporary_failure", retryable: true))
        #expect(a.transport.loads.count == 1)
        b.controller.dispose()
        #expect(a.controller.state == .preparing)
        #expect(a.transport.loads.count == 2, "the reload retry loads the page again")

        // A page that answered is told to prepare again once a slot frees.
        let box = InteractiveExperienceBox()
        let p = Harness(box: box)
        let q = Harness(box: box)
        p.controller.prepare()
        p.bridgeReady()
        p.runtime("prepare_failed", failedPrepare)
        #expect(p.controller.state == .failed(errorCode: "temporary_failure", retryable: true))
        q.controller.prepare()
        let r = Harness(box: box)
        r.controller.prepare()
        p.controller.retry()
        #expect(p.controller.state == .failed(errorCode: "temporary_failure", retryable: true))
        #expect(p.sentTypes == ["initialize"])
        q.controller.dispose()
        #expect(p.controller.state == .preparing)
        #expect(p.sentTypes == ["initialize", "retry_prepare"])

        // A form the viewer opened needs no slot, though both are taken.
        let opened = Harness(box: box)
        opened.controller.open()
        opened.bridgeReady()
        opened.runtime("prepare_failed", failedPrepare)
        opened.controller.retry()
        #expect(opened.controller.state == .preparing)
        #expect(opened.sentTypes == ["initialize", "retry_prepare"])
    }
}
