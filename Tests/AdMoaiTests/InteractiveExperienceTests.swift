@_spi(Testing) @testable import AdMoai
import Foundation
import Testing

/// The scenarios of `Sources/AdMoai/InteractiveExperience.feature`, one test per scenario, run
/// against the contract pack vendored in `Fixtures/interactive-experience/`.
struct InteractiveExperienceTests {
    private static let config = SDKConfig(baseUrl: "https://api.mock.admoai.com", apiVersion: "2025-11-01")
    private static let secretToken = "tok_SECRET_123"

    /// An SDK on a platform that can show the secure form view. The test host (macOS) cannot, so
    /// the ON arm sets it; scenario 6 covers the platform that cannot.
    private static func capableSDK() -> AdMoai {
        let sdk = AdMoai(config: config)
        sdk.interactiveExperienceBox.platformSupportsSecureFormView = true
        return sdk
    }

    /// Counts how often the SDK reads the key names. The protocol has no way to ask for a value.
    private final class SpyProvider: LeadFormValueProvider {
        var keys: Set<StandardAttributeKey>
        private(set) var keyReads = 0

        var availableKeys: Set<StandardAttributeKey> {
            keyReads += 1
            return keys
        }

        init(_ keys: Set<StandardAttributeKey>) {
            self.keys = keys
        }
    }

    // MARK: - Fixtures

    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/interactive-experience")

    private func fixtureData(_ path: String) throws -> Data {
        try Data(contentsOf: Self.fixtures.appendingPathComponent(path))
    }

    private func fixtureObject(_ path: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: fixtureData(path)) as? [String: Any])
    }

    private func descriptorFixture() throws -> [String: Any] {
        try #require(try fixtureObject("decision/creative-descriptor.json")["interactiveExperience"] as? [String: Any])
    }

    // MARK: - Request helpers

    private func build(_ sdk: AdMoai) -> DecisionRequest {
        sdk.createRequestBuilder().addPlacement(key: "ride_summary_banner").build()
    }

    private func extensionJSON(_ request: DecisionRequest) throws -> [String: Any]? {
        let data = try JSONEncoder().encode(request)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return root["interactiveExperience"] as? [String: Any]
    }

    private func hasExtensionKey(_ request: DecisionRequest) throws -> Bool {
        let data = try JSONEncoder().encode(request)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return root.keys.contains("interactiveExperience")
    }

    private func sameJSON(_ a: [String: Any]?, _ b: [String: Any]?) -> Bool {
        guard let a, let b else { return false }
        return NSDictionary(dictionary: a).isEqual(to: b)
    }

    // MARK: - Response helpers

    private func jsonString(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func creative(_ id: String, experience: Any? = nil, rawExperience: String? = nil) throws -> String {
        var fields = """
        "contents": [{"key": "title", "value": "Hi \(id)", "type": "string"}],
        "advertiser": {"id": "adv-\(id)"},
        "tracking": {},
        "metadata": {"adId": "ad-\(id)", "creativeId": "\(id)", "templateId": "t", "placementId": "p", "priority": "standard"}
        """
        if let rawExperience {
            fields += ", \"interactiveExperience\": \(rawExperience)"
        } else if let experience {
            try fields += ", \"interactiveExperience\": \(jsonString(experience))"
        }
        return "{\(fields)}"
    }

    private func decode(_ creatives: [[String]]) throws -> DecisionResponse {
        let placements = creatives.enumerated().map { index, list in
            "{\"placement\": \"slot_\(index)\", \"creatives\": [\(list.joined(separator: ","))]}"
        }
        return try JSONDecoder().decode(
            DecisionResponse.self,
            from: Data("[\(placements.joined(separator: ","))]".utf8)
        )
    }

    /// One placement with a sibling on each side of the creative under test.
    private func decodeAmongSiblings(_ middle: String) throws -> [Creative] {
        let response = try decode([[creative("a"), middle, creative("c")]])
        let creatives = try #require(response.first?.creatives)
        #expect(creatives.count == 3)
        #expect(creatives[0].advertiser.id == "adv-a")
        #expect(creatives[2].advertiser.id == "adv-c")
        #expect(creatives[0].interactiveExperience == nil)
        #expect(creatives[2].interactiveExperience == nil)
        return creatives
    }

    private func descriptor(with changes: [String: Any?]) throws -> [String: Any] {
        var object = try descriptorFixture()
        for (key, value) in changes {
            if let value {
                object[key] = value
            } else {
                object.removeValue(forKey: key)
            }
        }
        return object
    }

    // Scenario 1
    @Test func anSDKUpdateAloneDoesNotDeclareSupport() throws {
        let request = build(Self.capableSDK())
        #expect(try hasExtensionKey(request) == false)
        #expect(request.interactiveExperience == nil)
        let omitted = try fixtureObject("decision/request-omitted.json")
        #expect(omitted.keys.contains("interactiveExperience") == false)
    }

    // Scenario 2
    @Test func anOptedInAppDeclaresTheKeysItHoldsNeverTheValues() throws {
        let sdk = Self.capableSDK()
        let provider = SpyProvider([.email, .fullName, .phone])
        sdk.enableInteractiveExperiences(valueProvider: provider)

        let request = build(sdk)
        let expected =
            try fixtureObject("decision/request-supported-with-keys.json")["interactiveExperience"] as? [String: Any]
        #expect(try sameJSON(extensionJSON(request), expected))
        #expect(request.interactiveExperience?.availableAttributeKeys == [.fullName, .email, .phone])
        #expect(provider.keyReads == 1)
    }

    // Scenario 3
    @Test func anOptedInAppWithNoValuesStillDeclaresSupport() throws {
        let sdk = Self.capableSDK()
        sdk.enableInteractiveExperiences(valueProvider: SpyProvider([]))

        let expected =
            try fixtureObject("decision/request-supported-empty-keys.json")["interactiveExperience"] as? [String: Any]
        #expect(try sameJSON(extensionJSON(build(sdk)), expected))
    }

    // Scenario 4
    @Test func keysAreReadWhenEachRequestIsBuilt() {
        let sdk = Self.capableSDK()
        let provider = SpyProvider([.email])
        sdk.enableInteractiveExperiences(valueProvider: provider)

        let first = build(sdk)
        provider.keys = [.phone]
        let second = build(sdk)

        #expect(first.interactiveExperience?.availableAttributeKeys == [.email])
        #expect(second.interactiveExperience?.availableAttributeKeys == [.phone])
    }

    // Scenario 5
    @Test func optingOutStopsDeclaring() throws {
        let sdk = Self.capableSDK()
        sdk.enableInteractiveExperiences(valueProvider: SpyProvider([.email]))
        #expect(try hasExtensionKey(build(sdk)) == true)

        sdk.disableInteractiveExperiences()
        #expect(try hasExtensionKey(build(sdk)) == false)
        #expect(sdk.interactiveExperiencesEnabled == false)
    }

    // Scenario 6
    @Test func aPlatformWithoutASecureFormViewDeclaresNothing() throws {
        #if !(canImport(WebKit) && canImport(UIKit))
            #expect(AdMoai(config: Self.config).interactiveExperienceBox.platformSupportsSecureFormView == false)
        #endif
        let sdk = Self.capableSDK()
        sdk.interactiveExperienceBox.platformSupportsSecureFormView = false
        sdk.enableInteractiveExperiences(valueProvider: SpyProvider([.email]))

        #expect(try hasExtensionKey(build(sdk)) == false)
        #expect(sdk.interactiveExperiencesEnabled == false)
    }

    // Scenario 7
    @Test func everyCopyOfTheSDKSharesTheOptIn() throws {
        let sdk = Self.capableSDK()
        let copy = sdk
        sdk.enableInteractiveExperiences(valueProvider: SpyProvider([.age]))

        #expect(copy.interactiveExperiencesEnabled == true)
        #expect(copy.createRequestBuilder().addPlacement(key: "x").build().interactiveExperience?
            .availableAttributeKeys == [.age])
    }

    // Scenario 8
    @Test func theTypedKeysAreTheContractsInOrder() throws {
        let catalog = try fixtureObject("standard-fields.json")
        let prefillKeys = try #require(catalog["prefillKeys"] as? [String])
        let fieldKeys = try #require((catalog["fields"] as? [[String: Any]])?.compactMap { $0["key"] as? String })
        #expect(StandardAttributeKey.allCases.map(\.rawValue) == prefillKeys)
        #expect(StandardAttributeKey.allCases.map(\.rawValue) == fieldKeys)
    }

    // Scenario 9
    @Test func aLeadGenerationDescriptorIsDecodedPerCreative() throws {
        let response = try decode([
            [creative("a"), creative("b", experience: descriptorFixture())],
            [creative("c")],
        ])
        let all = response.flatMap { $0.creatives ?? [] }
        #expect(all.count == 3)

        let expected = try LeadGenerationExperience(
            formId: "form_01KG000000000000000000F001",
            preparedVersionId: "form_version_01KG000000000000000000V002",
            formInstanceId: "form_instance_01KG000000000000000000N001",
            launchUrl: #require(
                URL(string: "https://api.tenant.example.invalid/interactive-experiences/runtime/index.html")
            ),
            expiresAt: Date(timeIntervalSince1970: 1_794_496_500),
            prefillAttributeKeys: [.fullName, .email],
            preparationToken: "REDACTED_PREPARATION_TOKEN"
        )
        #expect(all[1].interactiveExperience == .leadGeneration(expected))
        #expect(ISO8601DateFormatter().string(from: expected.expiresAt) == "2026-11-12T15:15:00Z")
        #expect(all[0].interactiveExperience == nil)
        #expect(all[2].interactiveExperience == nil)
        #expect(all[0].advertiser.id == "adv-a")
        #expect(all[0].contents.first?.key == "title")
        #expect(all[2].advertiser.id == "adv-c")
    }

    // Scenario 10
    @Test func anUnknownExperienceTypeIsUnusableButTheResponseStillDecodes() throws {
        let creatives = try decodeAmongSiblings(creative("b", experience: ["type": "quiz", "questions": [1, 2]]))
        #expect(creatives[1].interactiveExperience == .unsupported(type: "quiz"))
        #expect(creatives[1].advertiser.id == "adv-b")
    }

    // Scenario 11
    @Test func aMalformedDescriptorIsUnusableButTheResponseStillDecodes() throws {
        let cases: [(name: String, experience: String, type: String?)] = try [
            ("missing formId", jsonString(descriptor(with: ["formId": nil])), "lead_generation"),
            ("empty preparationToken", jsonString(descriptor(with: ["preparationToken": ""])), "lead_generation"),
            (
                "http launchUrl",
                jsonString(descriptor(with: ["launchUrl": "http://api.tenant.example.invalid/x"])),
                "lead_generation"
            ),
            ("unparsable expiresAt", jsonString(descriptor(with: ["expiresAt": "next tuesday"])), "lead_generation"),
            ("descriptor is a string", "\"lead_generation\"", nil),
            ("type is a number", jsonString(descriptor(with: ["type": 7])), nil),
        ]
        for testCase in cases {
            let creatives = try decodeAmongSiblings(creative("b", rawExperience: testCase.experience))
            #expect(creatives[1].interactiveExperience == .unsupported(type: testCase.type), "\(testCase.name)")
            #expect(creatives[1].advertiser.id == "adv-b", "\(testCase.name)")
        }
    }

    // Scenario 12
    @Test func unknownPrefillKeysAreDropped() throws {
        let object = try descriptor(with: ["prefillAttributeKeys": ["email", "homeAddress", "email", 3]])
        let creatives = try decodeAmongSiblings(creative("b", experience: object))
        guard case let .leadGeneration(experience)? = creatives[1].interactiveExperience else {
            Issue.record("expected a Lead Generation experience")
            return
        }
        #expect(experience.prefillAttributeKeys == [.email])
    }

    // Scenario 13
    @Test func thePreparationTokenNeverAppearsInDebugOutput() throws {
        for token in ["REDACTED_PREPARATION_TOKEN", Self.secretToken] {
            let object = try descriptor(with: ["preparationToken": token])
            let creatives = try decodeAmongSiblings(creative("b", experience: object))
            let held = try #require(creatives[1].interactiveExperience)
            guard case let .leadGeneration(experience) = held else {
                Issue.record("expected a Lead Generation experience")
                return
            }

            var dumped = ""
            dump(experience, to: &dumped)
            dump(held, to: &dumped)
            dump(creatives[1], to: &dumped)
            var printed = ""
            print(experience, held, creatives[1], to: &printed)

            let outputs = [
                String(describing: experience), String(reflecting: experience),
                String(describing: held), String(reflecting: held),
                String(describing: creatives[1]), String(reflecting: creatives[1]),
                dumped, printed,
            ]
            for output in outputs {
                #expect(output.contains(token) == false, "token leaked: \(output)")
            }
            // The redaction must not hide everything else.
            #expect(String(describing: experience).contains("form_instance_01KG000000000000000000N001"))
        }
    }

    // Scenario 14
    @Test func aScenarioRunnerCanDeclareWhatACapableDeviceWould() throws {
        let sdk = AdMoai(config: Self.config)
        sdk.interactiveExperienceBox.platformSupportsSecureFormView = false
        let previous = sdk.platformSupportsSecureFormViewForTesting
        #expect(previous == false)

        sdk.assumeSecureFormViewForTesting(true)
        sdk.enableInteractiveExperiences(valueProvider: SpyProvider([.email]))
        #expect(try extensionJSON(build(sdk)) != nil)

        sdk.assumeSecureFormViewForTesting(previous)
        #expect(try hasExtensionKey(build(sdk)) == false)
    }
}
