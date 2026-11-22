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

        func leadFormController(_: LeadFormController, didChange state: LeadFormState) {
            states.append(state)
        }

        func leadFormControllerDidRequestClose(_: LeadFormController) {
            closeRequests += 1
        }
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

        init(presentation: LeadFormPresentation = .fullScreen, expiresIn: TimeInterval = 3600) {
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
                now: { clock.date }
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

        func activated() {
            let url = { (tag: String) in JSONValue.string("https://api.example.invalid/track?t=\(tag)") }
            runtime("activated", [
                "formVersionId": .string("form_version_01KG000000000000000000V003"),
                "requestedAttributeKeys": .array([.string("email")]),
                "events": .array([
                    .object(["name": .string("form_open"), "url": url("a")]),
                    .object(["name": .string("form_start"), "url": url("b")]),
                ]),
            ])
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
    @Test func theWholeHappyPath() {
        let h = Harness()
        h.reachVisible()
        #expect(h.sentTypes == ["initialize", "activate", "prefill", "became_visible"])
        #expect(h.recorder.states == [.preparing, .prepared, .activating, .readyToShow, .visible])
        let load = h.transport.loads.first
        #expect(load?.fragment == "instanceId=\(Self.instanceId)&channel=\(h.controller.channel)")
        #expect(load?.absoluteString.hasPrefix("https://forms.example.invalid/launch?x=1#") == true)
        #expect(h.sent[0].payload["preparationToken"] == .string(Self.secret))
        #expect(h.sent[2].payload == ["values": .object([:])])
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
        #expect(h.controller.state == .failed(retryable: true))
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
        #expect(fatal.controller.state == .failed(retryable: false))
        #expect(fatal.sentTypes == ["initialize"])
    }

    // Scenario 7
    @Test func aRetryableFailureWhileActivatingIsRetriedByActivatingAgain() {
        let h = Harness()
        h.controller.open()
        h.bridgeReady()
        h.prepared()
        h.runtime("prepare_failed", ["errorCode": .string("rate_limited"), "retryable": .bool(true)])
        #expect(h.controller.state == .failed(retryable: true))
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
        #expect(other.controller.state == .failed(retryable: false))
    }

    // Scenario 9
    @Test func aPageThatSpeaksAnotherBridgeVersionIsUnavailable() {
        let h = Harness()
        h.controller.open()
        h.bridgeReady(version: "2")
        #expect(h.controller.state == .failed(retryable: false))
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
        #expect(h.controller.state == .failed(retryable: false))
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
        #expect(h.controller.state == .submitted(leadId: "lead_01KG000000000000000000W001"))

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
        #expect(!again.recorder.states.contains(.submitted(leadId: "lead_01KG000000000000000000W001")))
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
        #expect(h.recorder.states.last == .submitted(leadId: "lead_01KG000000000000000000W001"))
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

    // Scenario 20
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

    // Scenario 21
    @Test func prepareFailureCodesDecideWhetherARetryCanHelp() {
        let cases: [(code: String, flag: Bool, state: LeadFormState)] = [
            ("expired", true, .expired),
            ("revoked", true, .failed(retryable: false)),
            ("form_not_available", true, .failed(retryable: false)),
            ("unauthorized", true, .failed(retryable: false)),
            ("rate_limited", true, .failed(retryable: true)),
            ("temporary_failure", true, .failed(retryable: true)),
            ("temporary_failure", false, .failed(retryable: false)),
        ]
        for item in cases {
            let h = Harness()
            h.controller.prepare()
            h.bridgeReady()
            h.runtime("prepare_failed", ["errorCode": .string(item.code), "retryable": .bool(item.flag)])
            #expect(h.controller.state == item.state, "\(item.code) retryable \(item.flag)")
        }
    }

    // Scenario 22
    @Test func aPageThatCannotLoadIsReloadedOnRetry() {
        let offline = Harness()
        offline.controller.prepare()
        offline.transport.onLoadFailed?(.transient)
        #expect(offline.controller.state == .failed(retryable: true))
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
        lost.controller.retry()
        #expect(lost.transport.loads.count == 2)
        #expect(!lost.sentTypes.contains("retry_prepare"))
        lost.bridgeReady()
        #expect(lost.sentTypes == ["initialize", "initialize"])
    }

    // Scenario 23
    @Test func losingTheRendererAfterActivationIsFinal() {
        let h = Harness()
        h.controller.open()
        h.bridgeReady()
        h.prepared()
        h.activated()
        h.transport.onLoadFailed?(.transient)
        #expect(h.controller.state == .failed(retryable: false))
        h.controller.retry()
        #expect(h.transport.loads.count == 1)
        #expect(h.controller.state == .failed(retryable: false))
    }

    // Scenario 19
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
        #expect(
            sdk.makeLeadFormController(for: experience, presentation: .inline) == nil,
            "no secure view on this host"
        )
        sdk.interactiveExperienceBox.platformSupportsSecureFormView = true
        let controller = sdk.makeLeadFormController(for: experience, presentation: .inline)
        #expect(controller != nil)
        controller?.dispose()
    }

    // Scenario 24
    @Test func aFormThePageServerRefusesEndsAtOnce() {
        let h = Harness()
        h.controller.open()
        h.transport.onLoadFailed?(.unavailable) // e.g. 404 form_not_available, Lead Generation off
        #expect(h.controller.state == .failed(retryable: false))
        h.controller.retry()
        #expect(h.transport.loads.count == 1, "nothing to reload: the server does not serve the form")
        #expect(h.sentTypes.isEmpty)
    }
}
