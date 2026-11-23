@_spi(InteractiveExperience) @testable import AdMoai
import Foundation
import Testing
#if canImport(UIKit)
    import UIKit
    #if canImport(OSLog)
        import OSLog
    #endif

    /// The scenarios of `Sources/AdMoai/LeadFormView.feature`. The view reports to a real
    /// controller driven through a fake transport; what the controller does is checked in
    /// `LeadFormControllerTests`.
    @MainActor
    struct LeadFormViewTests {
        private static let instanceId = "form_instance_01KG000000000000000000N001"

        private final class FakeTransport: LeadFormTransport {
            var onMessage: ((String) -> Void)?
            var onLoadFailed: ((LeadFormLoadFailure) -> Void)?
            func load(_: URL) {}
            func send(_: String) {}
            func teardown() {}
        }

        private final class Recorder: LeadFormControllerDelegate {
            var states: [LeadFormState] = []
            func leadFormController(_: LeadFormController, didChange state: LeadFormState) {
                states.append(state)
            }

            func leadFormControllerDidRequestClose(_: LeadFormController) {}
        }

        @MainActor
        private struct Harness {
            let transport = FakeTransport()
            let recorder = Recorder()
            let controller: LeadFormController

            init() {
                let experience = LeadGenerationExperience(
                    formId: "form_1",
                    preparedVersionId: "form_version_01KG000000000000000000V002",
                    formInstanceId: LeadFormViewTests.instanceId,
                    launchUrl: URL(string: "https://forms.example.invalid/launch")!,
                    expiresAt: Date().addingTimeInterval(3600),
                    prefillAttributeKeys: [.email],
                    preparationToken: "tok"
                )
                controller = LeadFormController(
                    experience: experience,
                    presentation: .inline,
                    transport: transport,
                    logger: Logger(subsystem: "test", category: "LeadFormViewTests")
                )
                controller.delegate = recorder
            }

            private func runtime(_ type: String, _ payload: [String: JSONValue] = [:]) {
                let text = try? BridgeEnvelope(
                    type: type, instanceId: LeadFormViewTests.instanceId,
                    channel: controller.channel, payload: payload
                ).encoded()
                transport.onMessage?(text ?? "")
            }

            /// Brings the controller to `readyToShow`, waiting for the surface to be seen.
            func reachReadyToShow() {
                controller.open()
                runtime("bridge_ready", ["runtimeVersion": .string("1.0.0"), "bridgeVersion": .string("1")])
                runtime("prepared", ["preparedVersionId": .string("form_version_01KG000000000000000000V002")])
                runtime("activated", [
                    "formVersionId": .string("form_version_01KG000000000000000000V003"),
                    "requestedAttributeKeys": .array([.string("email")]),
                    "events": .array([.object([
                        "name": .string("form_open"),
                        "url": .string("https://api.example.invalid/track?t=a"),
                    ])]),
                ])
                runtime("prefill_applied")
            }
        }

        // Scenario 1 and 2: the pure rule the container applies.
        @Test func visibilityNeedsAWindowTheForegroundAndAClearChain() {
            let clear: [(isHidden: Bool, alpha: CGFloat)] = [(false, 1), (false, 1)]
            #expect(LeadFormView.isVisible(hasWindow: true, inBackground: false, chain: clear))
            #expect(!LeadFormView.isVisible(hasWindow: false, inBackground: false, chain: clear))
            #expect(!LeadFormView.isVisible(hasWindow: true, inBackground: true, chain: clear))
            #expect(!LeadFormView.isVisible(hasWindow: true, inBackground: false, chain: [(false, 1), (true, 1)]))
            #expect(!LeadFormView.isVisible(hasWindow: true, inBackground: false, chain: [(false, 0), (false, 1)]))
        }

        // Scenario 4: a scene decides for its windows; the app decides for a window with no scene.
        @Test func aSceneInTheBackgroundHidesItsWindowsWhateverTheAppSays() {
            #expect(!LeadFormView.isInBackground(sceneState: .foregroundActive, applicationState: .background))
            #expect(!LeadFormView.isInBackground(sceneState: .foregroundInactive, applicationState: .active))
            #expect(LeadFormView.isInBackground(sceneState: .background, applicationState: .active))
            #expect(LeadFormView.isInBackground(sceneState: .unattached, applicationState: .active))
            #expect(LeadFormView.isInBackground(sceneState: nil, applicationState: .background))
            #expect(!LeadFormView.isInBackground(sceneState: nil, applicationState: .inactive))
        }

        // Scenario 3: hiding an ancestor, not only the view, hides the form.
        @Test func hidingOrFadingAnAncestorHidesTheForm() {
            let h = Harness()
            h.reachReadyToShow()
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
            window.isHidden = false
            let grandparent = UIView(frame: window.bounds)
            let parent = UIView(frame: window.bounds)
            let view = LeadFormView(content: nil, presentation: .inline, controller: h.controller)
            parent.addSubview(view)
            grandparent.addSubview(parent)
            window.addSubview(grandparent)
            #expect(h.controller.state == .visible)

            grandparent.isHidden = true
            #expect(h.controller.state == .readyToShow)
            grandparent.isHidden = false
            #expect(h.controller.state == .visible)

            parent.alpha = 0
            #expect(h.controller.state == .readyToShow)
            parent.alpha = 1
            #expect(h.controller.state == .visible)

            // Moved out of the hierarchy, the old ancestors no longer matter.
            view.removeFromSuperview()
            #expect(h.controller.state == .readyToShow)
            parent.isHidden = true
            parent.isHidden = false
            #expect(h.controller.state == .readyToShow)
        }

        // Scenario 4: the notifications of the window's own scene move visibility.
        @Test func theWindowsSceneEnteringTheBackgroundHidesTheForm() throws {
            let h = Harness()
            h.reachReadyToShow()
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
            window.isHidden = false
            let view = LeadFormView(content: nil, presentation: .inline, controller: h.controller)
            window.addSubview(view)
            let scene = try #require(window.windowScene, "the test host gives windows a scene")
            #expect(h.controller.state == .visible)

            // The app as a whole going to the background is not this scene's word.
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            #expect(h.controller.state == .visible)
            // Another scene is not ours either.
            NotificationCenter.default.post(name: UIScene.didEnterBackgroundNotification, object: NSObject())
            #expect(h.controller.state == .visible)

            NotificationCenter.default.post(name: UIScene.didEnterBackgroundNotification, object: scene)
            #expect(h.controller.state == .readyToShow)
            NotificationCenter.default.post(name: UIScene.willEnterForegroundNotification, object: scene)
            #expect(h.controller.state == .visible)
        }
    }
#endif
