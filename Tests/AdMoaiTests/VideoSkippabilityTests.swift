import Foundation
import Testing

@testable import AdMoai

// Video skippability — cross-SDK parity
//
// Feature: Report skippability from what the engine actually sends
//   As a publisher SDK
//   I want isSkippable()/getSkipOffset() to resolve from the engine-owned metadata, and from
//   the creative's content fields whichever casing they arrive in
//   So that a player can honour skippability instead of silently never offering skip
//
// Both helpers were unable to return a useful answer:
//
//   1. They matched the content keys `isSkippable`/`skipOffset` in camelCase, but the platform
//      creates template fields in snake_case — a live journey video serve returns
//      `is_skippable`/`skip_offset`, the only such keys in the whole template_fields table.
//   2. `isSkippable()` additionally cast `Content.value` (an `AnyCodable`) straight to `Bool`,
//      which can never succeed; the cast has to go through the wrapped value, as `Content`'s own
//      documentation says.
//
// So isSkippable() returned false unconditionally and getSkipOffset() returned nil on every live
// serve. Neither helper had any test coverage, which is why it survived. Point 1 is the same class
// of defect as #2483 — the journey click resolver matched a hand-maintained snake_case list while
// the platform wrote camelCase — the same seam, the opposite direction. The Flutter and Android
// SDKs carried point 1 and are fixed alongside this.

private func decodeCreative(contents: String, metadata: String? = nil) throws -> Creative {
    let json = """
        {
          "contents": [\(contents)],
          "advertiser": {},
          "template": {"key": "normal_video"},
          "tracking": {},
          "delivery": "json"\(metadata.map { ", \"metadata\": \($0)" } ?? "")
        }
        """
    return try JSONDecoder().decode(Creative.self, from: json.data(using: .utf8)!)
}

private func metadataJSON(_ extra: String = "") -> String {
    """
    {
      "adId": "a",
      "creativeId": "c",
      "templateId": "t",
      "placementId": "p",
      "priority": "standard"\(extra.isEmpty ? "" : ", \(extra)")
    }
    """
}

struct VideoSkippabilityTests {

    // MARK: - snake_case content keys: the shape a live serve actually returns

    // Scenario: is_skippable arrives as integer 1
    @Test
    func testSnakeCaseIntegerOneIsSkippable() throws {
        let creative = try decodeCreative(
            contents: """
                {"key": "is_skippable", "value": 1, "type": "integer"},
                {"key": "skip_offset", "value": "5", "type": "text"}
                """)

        #expect(creative.isSkippable())
        #expect(creative.getSkipOffset() == "5")
    }

    // Scenario: is_skippable arrives as integer 0
    @Test
    func testSnakeCaseIntegerZeroIsNotSkippable() throws {
        let creative = try decodeCreative(
            contents: """{"key": "is_skippable", "value": 0, "type": "integer"}""")

        #expect(creative.isSkippable() == false)
    }

    // Scenario: is_skippable arrives as the string "true"
    @Test
    func testSnakeCaseStringTrueIsSkippable() throws {
        let creative = try decodeCreative(
            contents: """{"key": "is_skippable", "value": "true", "type": "integer"}""")

        #expect(creative.isSkippable())
    }

    // Scenario: a boolean value resolves through the AnyCodable wrapper
    @Test
    func testBooleanValueResolvesThroughAnyCodable() throws {
        // The defect this pins: `value as? Bool` on an AnyCodable always failed, so even a
        // correctly-keyed boolean reported not-skippable.
        let creative = try decodeCreative(
            contents: """{"key": "is_skippable", "value": true, "type": "integer"}""")

        #expect(creative.isSkippable())
    }

    // Scenario: placeholder seed text degrades instead of guessing or crashing
    @Test
    func testPlaceholderValueIsNotSkippable() throws {
        // The mock seed fills these fields with placeholder text.
        let creative = try decodeCreative(
            contents: """
                {"key": "is_skippable", "value": "is_skippable (demo)", "type": "integer"},
                {"key": "skip_offset", "value": "Journey Ad demo", "type": "text"}
                """)

        #expect(creative.isSkippable() == false)
        #expect(creative.getSkipOffset() == "Journey Ad demo")
    }

    // MARK: - camelCase content keys keep working

    // Scenario: legacy camelCase keys remain supported
    @Test
    func testCamelCaseKeysStillSupported() throws {
        let creative = try decodeCreative(
            contents: """
                {"key": "isSkippable", "value": true, "type": "integer"},
                {"key": "skipOffset", "value": "00:00:05", "type": "text"}
                """)

        #expect(creative.isSkippable())
        #expect(creative.getSkipOffset() == "00:00:05")
    }

    // MARK: - engine metadata wins over content

    // Scenario: metadata.isSkippable takes precedence
    @Test
    func testMetadataIsSkippableWins() throws {
        let creative = try decodeCreative(
            contents: """{"key": "is_skippable", "value": 0, "type": "integer"}""",
            metadata: metadataJSON("\"isSkippable\": true"))

        #expect(creative.isSkippable())
    }

    // Scenario: metadata.skipOffsetSeconds takes precedence
    @Test
    func testMetadataSkipOffsetSecondsWins() throws {
        let creative = try decodeCreative(
            contents: """{"key": "skip_offset", "value": "99", "type": "text"}""",
            metadata: metadataJSON("\"skipOffsetSeconds\": 5"))

        #expect(creative.getSkipOffset() == "5")
    }

    // Scenario: content is used when metadata omits the fields
    @Test
    func testContentUsedWhenMetadataOmitsFields() throws {
        let creative = try decodeCreative(
            contents: """
                {"key": "is_skippable", "value": 1, "type": "integer"},
                {"key": "skip_offset", "value": "7", "type": "text"}
                """,
            metadata: metadataJSON())

        #expect(creative.isSkippable())
        #expect(creative.getSkipOffset() == "7")
    }

    // MARK: - absent everywhere

    // Scenario: neither metadata nor content carries the fields
    @Test
    func testAbsentEverywhere() throws {
        let creative = try decodeCreative(contents: "")

        #expect(creative.isSkippable() == false)
        #expect(creative.getSkipOffset() == nil)
    }
}
