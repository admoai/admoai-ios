import Foundation
import Testing

@testable import AdMoai

/// Sponsored Pin Locations — distance requests, Matched Point models, point tracking.
///
/// Test names carry the acceptance-criteria numbers from
/// `features/sponsored-pin-locations/specs/E11-sdk.md`, the way the E06 suite carries its
/// parity-matrix ids, so a criterion and the test that proves it are greppable from either end.
///
/// The one criterion with no test here is **8c** (no bulk tap or click exists): the absence of
/// an API is not observable at runtime, so it is a review item rather than an assertion.

private let baseURL = "https://api.mock.admoai.com"

private func encodedJSON(_ request: DecisionRequest) throws -> String {
    String(data: try JSONEncoder().encode(request), encoding: .utf8)!
}

private func builder() -> DecisionRequestBuilder {
    AdMoai(config: SDKConfig(baseUrl: baseURL)).createRequestBuilder().addPlacement(key: "map")
}

/// A creative envelope with whatever `contents` the scenario needs.
private func decodeCreative(contents: String) throws -> Creative {
    let json = """
        {
          "contents": \(contents),
          "advertiser": { "name": "Cabify" },
          "tracking": { "impressions": [{ "key": "default", "url": "https://t/imp" }],
                        "clicks": [{ "key": "default", "url": "https://t/click" }] }
        }
        """
    return try JSONDecoder().decode(Creative.self, from: Data(json.utf8))
}

private let onePoint = """
    [{
      "key": "matched_points",
      "type": "matched_points",
      "value": [{
        "id": "advertiser_location_01ARZ3NDEKTSV4RRFFQ69G5FAV",
        "name": "Parque Arauco",
        "address": "Parque Arauco, Santiago",
        "latitude": -33.4030,
        "longitude": -70.5680,
        "distance": 1834,
        "clickUrl": "https://shop.example/parque-arauco",
        "tracking": {
          "views":  [{ "key": "default", "url": "https://t/pin/view" }],
          "taps":   [{ "key": "default", "url": "https://t/pin/tap" }],
          "clicks": [{ "key": "default", "url": "https://t/pin/click" }]
        }
      }]
    }]
    """

// MARK: - Request side

struct SponsoredPinRequestTests {

    /// AC1 — the radius overload builds a radius search and no bounds.
    @Test func radiusSearchSerializes() throws {
        let request = try builder()
            .setDistanceTargeting(latitude: -33.4175, longitude: -70.6065, radius: 8000)
            .build()
        let json = try encodedJSON(request)

        #expect(json.contains("\"distance\""))
        #expect(json.contains("\"radius\":8000"))
        #expect(json.contains("\"latitude\":-33.4175"))
        #expect(!json.contains("\"bounds\""))
    }

    /// AC1 — the bounds overload builds a rectangle, and keeps the origin.
    @Test func boundsSearchSerializes() throws {
        let request = try builder()
            .setDistanceTargeting(
                latitude: -33.4175, longitude: -70.6065,
                bounds: DistanceBounds(north: -33.38, south: -33.46, east: -70.54, west: -70.68)
            )
            .build()
        let json = try encodedJSON(request)

        #expect(json.contains("\"bounds\""))
        #expect(json.contains("\"north\":-33.38"))
        // "Nearest first" needs an origin, and the centre of a box is not necessarily the viewer.
        #expect(json.contains("\"latitude\":-33.4175"))
        #expect(!json.contains("\"radius\""))
    }

    /// AC4 — the limit is emitted when given and absent when not.
    @Test func limitIsEmittedOnlyWhenGiven() throws {
        let withLimit = try encodedJSON(
            try builder()
                .setDistanceTargeting(latitude: 0, longitude: 0, radius: 500, limit: 5)
                .build())
        let without = try encodedJSON(
            try builder()
                .setDistanceTargeting(latitude: 0, longitude: 0, radius: 500)
                .build())

        #expect(withLimit.contains("\"limit\":5"))
        #expect(!without.contains("\"limit\""))
    }

    /// AC5 — a request that never asks for pins carries no `distance` at all.
    @Test func noDistanceKeyWhenNeverSet() throws {
        let json = try encodedJSON(try builder().setGeoTargeting([123]).build())

        #expect(!json.contains("\"distance\""))
    }

    /// AC2 — coordinates off the globe are refused locally, not by a 422.
    @Test func refusesImpossibleOrigin() throws {
        #expect(throws: SDKError.self) {
            try builder().setDistanceTargeting(latitude: 91, longitude: 0, radius: 100)
        }
        #expect(throws: SDKError.self) {
            try builder().setDistanceTargeting(latitude: 0, longitude: -181, radius: 100)
        }
    }

    /// AC2 — a radius of zero or less is a bug worth refusing.
    @Test func refusesNonPositiveRadius() throws {
        #expect(throws: SDKError.self) {
            try builder().setDistanceTargeting(latitude: 0, longitude: 0, radius: 0)
        }
        #expect(throws: SDKError.self) {
            try builder().setDistanceTargeting(latitude: 0, longitude: 0, radius: -1)
        }
    }

    /// AC2 — a rectangle that encloses nothing is refused.
    @Test func refusesInvertedBounds() throws {
        #expect(throws: SDKError.self) {
            try builder().setDistanceTargeting(
                latitude: 0, longitude: 0,
                bounds: DistanceBounds(north: -33.46, south: -33.38, east: -70.54, west: -70.68))
        }
    }

    /// AC2 — V1 refuses an antimeridian crossing, keeping `west < east` flat.
    @Test func refusesAntimeridianBounds() throws {
        #expect(throws: SDKError.self) {
            try builder().setDistanceTargeting(
                latitude: 0, longitude: 179,
                bounds: DistanceBounds(north: 10, south: -10, east: -179, west: 179))
        }
    }

    /// AC2 — asking for no points is a bug, not a way to ask for all of them.
    @Test func refusesNonPositiveLimit() throws {
        #expect(throws: SDKError.self) {
            try builder().setDistanceTargeting(latitude: 0, longitude: 0, radius: 100, limit: 0)
        }
    }

    /// AC3 — the SDK hard-codes NO ceiling. 50 km and 100 km are server policy, and a client
    /// that bakes them in refuses what a newer engine would accept.
    @Test func acceptsRadiusAboveTheServersCurrentCeiling() throws {
        let json = try encodedJSON(
            try builder()
                .setDistanceTargeting(latitude: 0, longitude: 0, radius: 80_000)
                .build())

        #expect(json.contains("\"radius\":80000"))
    }

    /// AC3 — likewise for a rectangle larger than today's diagonal limit.
    @Test func acceptsBoundsLargerThanTheServersCurrentCeiling() throws {
        let json = try encodedJSON(
            try builder()
                .setDistanceTargeting(
                    latitude: 0, longitude: 0,
                    bounds: DistanceBounds(north: 5, south: -5, east: 5, west: -5)
                )
                .build())

        #expect(json.contains("\"bounds\""))
    }

    /// AC2 — the failure names the field, and carries no URL or coordinate soup.
    @Test func refusalReasonNamesTheField() throws {
        #expect(SDKError.invalidDistanceRadius(0).description.contains("radius"))
        #expect(SDKError.invalidDistanceLimit(0).description.contains("limit"))
        #expect(SDKError.invalidDistanceBounds("require north greater than south")
            .description.contains("north"))
    }

    @Test func clearRemovesTheSearchAndNothingElse() throws {
        let json = try encodedJSON(
            try builder()
                .setDistanceTargeting(latitude: 0, longitude: 0, radius: 100)
                .setGeoTargeting([42])
                .clearDistanceTargeting()
                .build())

        #expect(!json.contains("\"distance\""))
        #expect(json.contains("\"geo\":[42]"))
    }

    /// Setting another targeting axis afterwards must not silently drop the search — the
    /// builder copies its targeting on every setter, so each copy has to carry it forward.
    @Test func anotherTargetingAxisDoesNotDropTheSearch() throws {
        let json = try encodedJSON(
            try builder()
                .setDistanceTargeting(latitude: -33.4175, longitude: -70.6065, radius: 8000)
                .setGeoTargeting([42])
                .addLocationTargeting(latitude: 1, longitude: 2)
                .addCustomTargeting(key: "tier", value: "gold")
                .build())

        #expect(json.contains("\"radius\":8000"))
        #expect(json.contains("\"geo\":[42]"))
    }
}

// MARK: - Response side

struct SponsoredPinModelTests {

    /// AC4 — every field maps, in the server's order.
    @Test func matchedPointsDecodeWithEveryField() throws {
        let creative = try decodeCreative(contents: onePoint)
        let point = try #require(creative.matchedPoints.first)

        #expect(creative.matchedPoints.count == 1)
        #expect(point.id == "advertiser_location_01ARZ3NDEKTSV4RRFFQ69G5FAV")
        #expect(point.name == "Parque Arauco")
        #expect(point.address == "Parque Arauco, Santiago")
        #expect(point.latitude == -33.4030)
        #expect(point.longitude == -70.5680)
        #expect(point.distance == 1834)
        #expect(point.clickUrl == "https://shop.example/parque-arauco")
        #expect(point.tracking?.views?.first?.url == "https://t/pin/view")
    }

    /// AC5 — a creative with no such entry yields an empty list and no error.
    @Test func creativeWithoutMatchedPointsIsEmpty() throws {
        let creative = try decodeCreative(
            contents: #"[{ "key": "headline", "type": "text", "value": "Hi" }]"#)

        #expect(creative.matchedPoints.isEmpty)
        #expect(creative.contents.count == 1)
    }

    /// AC6 — a Sponsored Pin response stays parseable by code that knows nothing about pins:
    /// the entry decodes through `Content` as an ordinary content item, as it always did.
    @Test func matchedPointsRemainReadableAsAnOrdinaryContentEntry() throws {
        let creative = try decodeCreative(contents: onePoint)

        #expect(creative.contents.getContent(key: "matched_points") != nil)
        #expect(creative.contents.isType(key: "matched_points", type: "matched_points"))
    }

    /// An absent address or click URL is absent, never an empty string — an empty string reads
    /// to an app as a URL that happens to be blank, and the obvious handling is to navigate.
    @Test func absentAddressAndClickUrlAreNil() throws {
        let creative = try decodeCreative(
            contents: """
                [{ "key": "matched_points", "type": "matched_points", "value": [
                   { "id": "loc_1", "name": "Shop", "latitude": 1, "longitude": 2, "distance": 10 }
                ]}]
                """)
        let point = try #require(creative.matchedPoints.first)

        #expect(point.address == nil)
        #expect(point.clickUrl == nil)
        #expect(point.tracking == nil)
    }

    /// A point gaining a field in a later server release must not break a shipped app.
    @Test func unknownPointFieldsAreIgnored() throws {
        let creative = try decodeCreative(
            contents: """
                [{ "key": "matched_points", "type": "matched_points", "value": [
                   { "id": "loc_1", "name": "Shop", "latitude": 1, "longitude": 2,
                     "distance": 10, "openingHours": "9-5" }
                ]}]
                """)

        #expect(creative.matchedPoints.count == 1)
    }

    /// A malformed point drops; its siblings survive; the creative never fails.
    @Test func malformedPointIsDroppedAndSiblingsSurvive() throws {
        let creative = try decodeCreative(
            contents: """
                [{ "key": "matched_points", "type": "matched_points", "value": [
                   { "id": "loc_1", "name": "Good", "latitude": 1, "longitude": 2, "distance": 10 },
                   { "id": "loc_2" },
                   { "id": "loc_3", "name": "Also good", "latitude": 3, "longitude": 4, "distance": 20 }
                ]}]
                """)

        #expect(creative.matchedPoints.map(\.id) == ["loc_1", "loc_3"])
    }

    /// AC10 — points hang off their creative, so two winning ads cannot be confused. There is
    /// no flat "all matched points" list to get wrong.
    @Test func twoCreativesKeepTheirOwnPoints() throws {
        let a = try decodeCreative(contents: onePoint)
        let b = try decodeCreative(
            contents: """
                [{ "key": "matched_points", "type": "matched_points", "value": [
                   { "id": "loc_b", "name": "Other", "latitude": 9, "longitude": 9, "distance": 1 }
                ]}]
                """)

        #expect(a.matchedPoints.map(\.id) == ["advertiser_location_01ARZ3NDEKTSV4RRFFQ69G5FAV"])
        #expect(b.matchedPoints.map(\.id) == ["loc_b"])
    }
}

// MARK: - Point tracking

/// Nested under ``MockNetworkTests`` deliberately: `MockURLProtocol` keeps its stub and its
/// captured requests in `static` state, so a top-level suite would run alongside the other
/// network suites and see their requests. That failure looks exactly like an SDK bug — a test
/// asserting "nothing fired" finding somebody else's beacon.
extension MockNetworkTests {
    @Suite
    struct SponsoredPinTrackingTests {

    private func sdk() -> AdMoai {
        AdMoai(config: MockURLProtocol.config(apiVersion: "2025-11-01", defaultLanguage: "en"))
    }

    private func firedURLs() -> [String] {
        MockURLProtocol.capturedRequests.compactMap { $0.url?.absoluteString }
    }

    /// AC7 — parsing a response fires nothing. The SDK draws no map and cannot know what the
    /// user saw, so it never reports a view on anyone's behalf.
    @Test func parsingFiresNothing() async throws {
        MockURLProtocol.reset()

        let creative = try decodeCreative(contents: onePoint)
        _ = creative.matchedPoints.map(\.id)
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(firedURLs().isEmpty)
    }

    /// AC8 — each call fires exactly its own list and nothing else.
    @Test func eachHelperFiresItsOwnList() async throws {
        let creative = try decodeCreative(contents: onePoint)
        let point = try #require(creative.matchedPoints.first)

        MockURLProtocol.reset()
        sdk().trackPointView(point)
        await MockURLProtocol.waitForRequests(1)
        #expect(firedURLs() == ["https://t/pin/view"])

        MockURLProtocol.reset()
        sdk().trackPointTap(point)
        await MockURLProtocol.waitForRequests(1)
        #expect(firedURLs() == ["https://t/pin/tap"])

        MockURLProtocol.reset()
        sdk().trackPointClick(point)
        await MockURLProtocol.waitForRequests(1)
        #expect(firedURLs() == ["https://t/pin/click"])
    }

    /// AC12 — opening a detail card is a tap and never a click. This is the one that costs
    /// money when it is wrong, so it is asserted rather than documented.
    @Test func aTapNeverFiresTheClickBeacon() async throws {
        let creative = try decodeCreative(contents: onePoint)
        let point = try #require(creative.matchedPoints.first)

        MockURLProtocol.reset()
        sdk().trackPointTap(point)
        await MockURLProtocol.waitForRequests(1)

        #expect(!firedURLs().contains("https://t/pin/click"))
        #expect(!firedURLs().contains("https://t/click"))
    }

    /// AC8 — the point click replaces the creative click; it never also fires it.
    @Test func pointClickDoesNotFireTheCreativeClick() async throws {
        let creative = try decodeCreative(contents: onePoint)
        let point = try #require(creative.matchedPoints.first)

        MockURLProtocol.reset()
        sdk().trackPointClick(point)
        await MockURLProtocol.waitForRequests(1)

        #expect(firedURLs() == ["https://t/pin/click"])
    }

    /// A point with nothing to report reports nothing, and raises nothing.
    @Test func pointWithoutTrackingFiresNothing() async throws {
        let creative = try decodeCreative(
            contents: """
                [{ "key": "matched_points", "type": "matched_points", "value": [
                   { "id": "loc_1", "name": "Shop", "latitude": 1, "longitude": 2, "distance": 10 }
                ]}]
                """)
        let point = try #require(creative.matchedPoints.first)

        MockURLProtocol.reset()
        sdk().trackPointView(point)
        sdk().trackPointTap(point)
        sdk().trackPointClick(point)
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(firedURLs().isEmpty)
    }

    /// AC8b — the bulk form fires one view per point.
    @Test func bulkFiresOneViewPerPoint() async throws {
        let points = try threePoints()

        MockURLProtocol.reset()
        sdk().trackPointViews(points)
        await MockURLProtocol.waitForRequests(3)

        #expect(Set(firedURLs()) == ["https://t/a", "https://t/b", "https://t/c"])
    }

    /// AC8b — the same point named twice in one call is one view.
    @Test func bulkDeduplicatesWithinTheInvocation() async throws {
        let points = try threePoints()
        let first = try #require(points.first)

        MockURLProtocol.reset()
        sdk().trackPointViews([first, first, first])
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(firedURLs() == ["https://t/a"])
    }

    /// AC8b — two renders are two views. There is no de-duplication across invocations.
    @Test func bulkDoesNotDeduplicateAcrossInvocations() async throws {
        let points = try threePoints()
        let first = try #require(points.first)
        let sdk = self.sdk()

        MockURLProtocol.reset()
        sdk.trackPointViews([first])
        sdk.trackPointViews([first])
        await MockURLProtocol.waitForRequests(2)

        #expect(firedURLs() == ["https://t/a", "https://t/a"])
    }

    /// AC8b — an empty list is a no-op, not a crash.
    @Test func bulkWithNoPointsFiresNothing() async throws {
        MockURLProtocol.reset()
        sdk().trackPointViews([])
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(firedURLs().isEmpty)
    }

    /// AC8b — a point with nothing to report is skipped; its siblings still report.
    @Test func bulkSkipsUntrackablePointsWithoutAffectingSiblings() async throws {
        let creative = try decodeCreative(
            contents: """
                [{ "key": "matched_points", "type": "matched_points", "value": [
                   { "id": "a", "name": "A", "latitude": 1, "longitude": 1, "distance": 1,
                     "tracking": { "views": [{ "key": "default", "url": "https://t/a" }] } },
                   { "id": "silent", "name": "S", "latitude": 2, "longitude": 2, "distance": 2 }
                ]}]
                """)

        MockURLProtocol.reset()
        sdk().trackPointViews(creative.matchedPoints)
        await MockURLProtocol.waitForRequests(1)
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(firedURLs() == ["https://t/a"])
    }

    /// AC9 — the resolved destination is used verbatim; no SDK re-derives it from the creative.
    @Test func clickUrlIsUsedVerbatim() throws {
        let creative = try decodeCreative(contents: onePoint)
        let point = try #require(creative.matchedPoints.first)

        #expect(point.clickUrl == "https://shop.example/parque-arauco")
    }

    private func threePoints() throws -> [MatchedPoint] {
        try decodeCreative(
            contents: """
                [{ "key": "matched_points", "type": "matched_points", "value": [
                   { "id": "a", "name": "A", "latitude": 1, "longitude": 1, "distance": 1,
                     "tracking": { "views": [{ "key": "default", "url": "https://t/a" }] } },
                   { "id": "b", "name": "B", "latitude": 2, "longitude": 2, "distance": 2,
                     "tracking": { "views": [{ "key": "default", "url": "https://t/b" }] } },
                   { "id": "c", "name": "C", "latitude": 3, "longitude": 3, "distance": 3,
                     "tracking": { "views": [{ "key": "default", "url": "https://t/c" }] } }
                ]}]
                """
        ).matchedPoints
    }
}
}
