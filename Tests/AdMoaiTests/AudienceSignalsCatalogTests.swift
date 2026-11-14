@testable import AdMoai
import Foundation
import Testing

/// The typed audience enums against the Standard catalog generated in adhub (vendored in
/// `Fixtures/audience-signals/`): same keys in the same order, same wire values in the same order.
/// A catalog change in adhub that the SDK has not followed fails here, not in production.
struct AudienceSignalsCatalogTests {
    private struct Catalog: Decodable {
        struct Preset: Decodable {
            struct Value: Decodable { let value: String }
            let key: String
            let requestShape: String
            let values: [Value]
        }

        let presets: [Preset]
    }

    private func catalog() throws -> Catalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/audience-signals/catalog.generated.json")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    private func values(_ key: String) throws -> [String] {
        let preset = try #require(try catalog().presets.first { $0.key == key }, "catalog has \(key)")
        return preset.values.map(\.value)
    }

    @Test func keysMatchTheCatalogInOrder() throws {
        #expect(try AudienceSignals.Key.allCases.map(\.rawValue) == (catalog().presets.map(\.key)))
    }

    @Test func requestShapesMatchTheCatalog() throws {
        for preset in try catalog().presets {
            let expected = preset.key == AudienceSignals.Key.publisherSegments.rawValue ? "string_array" : "string"
            #expect(preset.requestShape == expected, "\(preset.key) request shape")
        }
    }

    @Test func everyTypedValueMatchesTheCatalogInOrder() throws {
        #expect(try AudienceSignals.AgeGroup.allCases.map(\.rawValue) == values("age_group"))
        #expect(try AudienceSignals.Gender.allCases.map(\.rawValue) == values("gender"))
        #expect(try AudienceSignals.AccountType.allCases.map(\.rawValue) == values("account_type"))
        #expect(try AudienceSignals.SubscriptionStatus.allCases.map(\.rawValue) == values("subscription_status"))
        #expect(try AudienceSignals.AccountTenure.allCases.map(\.rawValue) == values("account_tenure"))
        #expect(try AudienceSignals.TripFrequency30d.allCases.map(\.rawValue) == values("trip_frequency_30d"))
        #expect(try AudienceSignals.LastTripRecency.allCases.map(\.rawValue) == values("last_trip_recency"))
        #expect(try values("publisher_segments").isEmpty, "segments are workspace-registered, never fixed")
    }
}
