@testable import AdMoai
import Foundation
import Testing

/// The scenarios of `Sources/AdMoai/AudienceSignals.feature`, one test per scenario.
struct AudienceSignalsTests {
    private static let config = SDKConfig(baseUrl: "https://api.mock.admoai.com", apiVersion: "2025-11-01")

    private func makeBuilder() -> DecisionRequestBuilder {
        AdMoai(config: Self.config).createRequestBuilder().addPlacement(key: "home")
    }

    private func json(_ request: DecisionRequest, sorted: Bool = false) throws -> [String: Any] {
        let encoder = JSONEncoder()
        if sorted {
            encoder.outputFormatting = [.sortedKeys]
        }
        let data = try encoder.encode(request)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func custom(_ request: DecisionRequest) throws -> [(key: String, value: Any)] {
        let root = try json(request)
        guard let targeting = root["targeting"] as? [String: Any],
              let entries = targeting["custom"] as? [[String: Any]]
        else { return [] }
        return entries.map { (key: $0["key"] as! String, value: $0["value"] as Any) }
    }

    private func segments(_ request: DecisionRequest) throws -> [String]? {
        try custom(request).first { $0.key == "publisher_segments" }?.value as? [String]
    }

    private func device(_ request: DecisionRequest) throws -> [String: Any]? {
        try json(request)["device"] as? [String: Any]
    }

    // Scenario 1
    @Test
    func typedHelperSendsTheCanonicalString() throws {
        let request = makeBuilder().setTripFrequency30d(.zero).setAgeGroup(.age18To24).build()
        let entries = try custom(request)
        #expect(entries.contains { $0.key == "trip_frequency_30d" && ($0.value as? String) == "0" })
        #expect(entries.contains { $0.key == "age_group" && ($0.value as? String) == "18_24" })
        let raw = try String(data: JSONEncoder().encode(request), encoding: .utf8)!
        #expect(raw.contains("\"value\":\"0\""))
    }

    // Scenario 2
    @Test
    func everyTypedValueMatchesTheCatalog() {
        #expect(AudienceSignals.Key.allCases.map(\.rawValue) == [
            "age_group", "gender", "account_type", "subscription_status", "account_tenure",
            "trip_frequency_30d", "last_trip_recency", "publisher_segments",
        ])
        #expect(AudienceSignals.AgeGroup.allCases.map(\.rawValue) == [
            "under_18", "18_24", "25_34", "35_44", "45_54", "55_64", "65_plus",
        ])
        #expect(AudienceSignals.Gender.allCases.map(\.rawValue) == ["female", "male", "other", "prefer_not_to_say"])
        #expect(AudienceSignals.AccountType.allCases.map(\.rawValue) == [
            "personal",
            "business",
            "family",
            "student",
            "other",
        ])
        #expect(AudienceSignals.SubscriptionStatus.allCases.map(\.rawValue) == [
            "none",
            "trial",
            "active",
            "paused",
            "expired",
        ])
        #expect(AudienceSignals.AccountTenure.allCases.map(\.rawValue) == ["0_30d", "31_90d", "91_365d", "366d_plus"])
        #expect(AudienceSignals.TripFrequency30d.allCases.map(\.rawValue) == ["0", "1_2", "3_9", "10_plus"])
        #expect(AudienceSignals.LastTripRecency.allCases.map(\.rawValue) == [
            "never", "0_7d", "8_30d", "31_90d", "91d_plus",
        ])
        #expect(DeviceCategory.allCases.map(\.rawValue) == ["phone", "tablet", "other"])
    }

    // Scenario 3
    @Test
    func segmentHelperProducesOneCanonicalArray() throws {
        let request = try makeBuilder()
            .setPublisherSegments(["airport_commuter", "high_value", "airport_commuter"]).build()
        #expect(try segments(request) == ["airport_commuter", "high_value"])
    }

    // Scenario 4
    @Test
    func oneSegmentCodeIsStillAnArray() throws {
        let request = try makeBuilder().setPublisherSegments(["high_value"]).build()
        #expect(try segments(request) == ["high_value"])
    }

    // Scenario 5
    @Test
    func emptySegmentListRemovesTheEntry() throws {
        let builder = try makeBuilder().setPublisherSegments(["high_value"])
        let request = try builder.setPublisherSegments([]).build()
        #expect(try segments(request) == nil)
        #expect(request.targeting?.custom == nil)
        let raw = try String(data: JSONEncoder().encode(request), encoding: .utf8)!
        #expect(!raw.contains("\"custom\":[]"))
    }

    // Scenario 6
    @Test
    func invalidSegmentSetterIsNotPartiallyApplied() throws {
        let builder = try makeBuilder().setPublisherSegments(["high_value"])
        #expect(throws: SDKError.invalidPublisherSegment(" padded")) {
            try builder.setPublisherSegments(["ok", " padded"])
        }
        #expect(try segments(builder.build()) == ["high_value"])
        #expect(throws: SDKError.invalidPublisherSegment("bad-code")) { try builder.setPublisherSegments(["bad-code"]) }
        #expect(throws: SDKError.invalidPublisherSegment("")) { try builder.setPublisherSegments([""]) }
        #expect(try segments(builder.build()) == ["high_value"])
        let message = SDKError.invalidPublisherSegment("bad-code").description
        #expect(message.contains("Invalid publisher segment code \"bad-code\""))
        #expect(message.contains("The builder was left unchanged."))
        _ = try builder.setPublisherSegments(["Mixed_Case_1"])
        #expect(try segments(builder.build()) == ["Mixed_Case_1"])
    }

    // Scenario 6b
    @Test
    func settingNilRemovesTheSegments() throws {
        let request = try makeBuilder()
            .addCustomTargeting(key: "theme", value: "dark")
            .setPublisherSegments(["a"])
            .setPublisherSegments(nil)
            .build()
        let entries = try custom(request)
        #expect(!entries.contains { $0.key == "publisher_segments" })
        #expect(entries.first { $0.key == "theme" }?.value as? String == "dark")
    }

    // Scenario 7
    @Test
    func latestExplicitSetterWinsBetweenTypedAndGeneric() throws {
        let builder = makeBuilder()
            .addCustomTargeting(key: "theme", value: "dark")
            .addCustomTargeting(key: "age_group", value: "18_24")
        var entries = try custom(builder.build())
        #expect(entries.filter { $0.key == "age_group" }.count == 1)
        _ = builder.setAgeGroup(.age35To44)
        entries = try custom(builder.build())
        #expect(entries.filter { $0.key == "age_group" }.count == 1)
        #expect(entries.first { $0.key == "age_group" }?.value as? String == "35_44")
        #expect(entries.first { $0.key == "theme" }?.value as? String == "dark")
        _ = builder.addCustomTargeting(key: "age_group", value: "25_34")
        entries = try custom(builder.build())
        #expect(entries.filter { $0.key == "age_group" }.count == 1)
        #expect(entries.first { $0.key == "age_group" }?.value as? String == "25_34")
        #expect(entries.first { $0.key == "theme" }?.value as? String == "dark")
    }

    // Scenario 8
    @Test
    func settingNilRemovesOnlyThatKey() throws {
        let builder = makeBuilder().setAgeGroup(.age25To34).setGender(.female)
        let entries = try custom(builder.setAgeGroup(nil).build())
        #expect(entries.map(\.key) == ["gender"])
        // Removing the last entry omits `custom`, and nil on a fresh builder creates nothing.
        let emptied = try custom(builder.setGender(nil).build())
        #expect(emptied.isEmpty)
        #expect(makeBuilder().setAgeGroup(nil).build().targeting == nil)
    }

    private func goldenSDK() -> AdMoai {
        var sdk = AdMoai(config: Self.config)
        sdk.setDeviceConfig(
            id: "dev-1", model: "iPhone", manufacturer: "Apple", os: "iOS", osVersion: "18.0",
            timezone: "UTC", language: "en"
        )
        sdk.setAppConfig(name: "App", version: "1.0", buildNumber: "7", identifier: "com.example.app", language: "en")
        return sdk
    }

    // Scenario 9
    @Test
    func goldenJSONIsUnchangedWhenNothingNewIsSet() throws {
        let request = goldenSDK().createRequestBuilder()
            .addPlacement(key: "home", count: 2, format: .native)
            .addGeoTargeting(5819)
            .addCustomTargeting(key: "category", value: "news")
            .setUserId("user-1")
            .build()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let actual = try String(data: encoder.encode(request), encoding: .utf8)!
        let expected =
            #"{"app":{"buildNumber":"7","identifier":"com.example.app","language":"en","name":"App","version":"1.0"},"#
                + #""device":{"id":"dev-1","language":"en","manufacturer":"Apple","model":"iPhone","os":"iOS","osVersion":"18.0","timezone":"UTC"},"#
                + #""placements":[{"count":2,"format":"native","key":"home"}],"#
                + #""targeting":{"custom":[{"key":"category","value":"news"}],"geo":[5819]},"#
                + #""user":{"consent":{"gdpr":false},"id":"user-1"}}"#
        #expect(actual == expected)
        #expect(!actual.contains("carrier"))
        #expect(!actual.contains("category\":\"") || actual.contains("\"key\":\"category\""))
    }

    // Scenario 10
    @Test
    func deviceCarrierAndCategoryAreSentWhenConfigured() throws {
        var sdk = goldenSDK()
        sdk.setDeviceCarrier("Example Mobile")
        sdk.setDeviceCategory(.phone)
        let device = try #require(try device(sdk.createRequestBuilder().addPlacement(key: "home").build()))
        #expect(device["carrier"] as? String == "Example Mobile")
        #expect(device["category"] as? String == "phone")
        // The original setDeviceConfig keeps both; nil on a dedicated setter removes only that one.
        sdk.setDeviceConfig(model: "iPhone16,1")
        sdk.setDeviceCarrier(nil)
        let after = try #require(try self.device(sdk.createRequestBuilder().addPlacement(key: "home").build()))
        #expect(after["carrier"] == nil)
        #expect(after["category"] as? String == "phone")
        #expect(after["model"] as? String == "iPhone16,1")
    }

    // Scenario 11
    @Test
    func carrierPlaceholdersAndWhitespaceBecomeAbsence() throws {
        var sdk = goldenSDK()
        sdk.setDeviceCarrier("  Example Mobile  ")
        #expect(try device(sdk.createRequestBuilder().addPlacement(key: "home").build())?["carrier"] as? String ==
            "Example Mobile")
        for raw in ["--", "Unknown", "WiFi", "wi-fi", "   "] {
            let config = DeviceConfig(
                id: "dev-1", model: nil, manufacturer: nil, os: nil, osVersion: nil, timezone: nil,
                language: nil, carrier: raw, category: nil
            )
            #expect(config.carrier == nil)
            let request = DecisionRequestBuilder(
                appConfig: .clear(), deviceConfig: config, userConfig: .clear()
            ).addPlacement(key: "home").build()
            #expect(try device(request)?.keys.contains("carrier") == false)
        }
    }

    // Scenario 12
    @Test
    func disablingDeviceCollectionOmitsTheWholeDeviceObject() throws {
        var sdk = goldenSDK()
        sdk.setDeviceCarrier("Example Mobile")
        sdk.setDeviceCategory(.tablet)
        let request = sdk.createRequestBuilder().addPlacement(key: "home").disableDeviceCollection().build()
        #expect(try json(request)["device"] == nil)
    }
}
