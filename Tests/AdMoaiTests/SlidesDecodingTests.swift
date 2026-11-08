@testable import AdMoai
import Foundation
import Testing

// Carousel slides and standard-format metadata, beyond the shared manifest
//
// Feature: A publisher's app reads a Carousel's slides and the standard format metadata
//   As a publisher's tech team
//   I want slides in server order and a decode that a malformed slide cannot break
//   So that one bad slide costs one slide, never the creative or the ad
//
// The shared fixture scenarios (FixtureScenariosTests) pin the golden wire; these pin the
// tolerance rules the golden files do not exercise.

private func creative(contents: String, metadata: String = "{}") throws -> Creative {
    let json = """
    {"success": true, "data": [{"placement": "home", "creatives": [{
        "contents": \(contents), "metadata": \(metadata), "advertiser": {}, "tracking": {}
    }]}]}
    """
    let body = try JSONDecoder().decode(APIResponseBody<DecisionResponse>.self, from: Data(json.utf8))
    return try #require(body.data?.first?.creatives?.first)
}

private func slide(_ id: String, _ position: Int) -> String {
    """
    {"slideId": "\(id)", "position": \(position),
     "contents": [{"key": "image", "value": "https://cdn.example/\(id).png", "type": "image"}],
     "tracking": {"views": [{"key": "slide_view", "url": "https://t.example/v/\(id)"}],
                  "clicks": [{"key": "default", "url": "https://t.example/c/\(id)"}]}}
    """
}

private func slides(_ entries: [String]) -> String {
    """
    [{"key": "slides", "type": "slides", "value": [\(entries.joined(separator: ","))]}]
    """
}

struct SlidesDecodingTests {
    @Test
    func testMalformedSlideIsDroppedAndOrderKept() throws {
        let bad = [
            #"{"position": 2, "contents": []}"#, // no slideId
            #"{"slideId": "s_bad", "position": "2"}"#, // mistyped position
            #"{"slideId": 7, "position": 2}"#, // mistyped slideId
            "42", // not an object
        ]
        let result = try creative(contents: slides([
            slide("a", 1),
            bad[0],
            slide("b", 2),
            bad[1],
            bad[2],
            bad[3],
            slide("c", 3),
        ]))
        #expect(result.slides.map(\.slideId) == ["a", "b", "c"])
        #expect(result.slides.map(\.position) == [1, 2, 3])
    }

    @Test
    func testPositionOutOfOrderOnTheWireKeepsWireOrder() throws {
        let result = try creative(contents: slides([slide("third", 3), slide("first", 1), slide("second", 2)]))
        #expect(result.slides.map(\.slideId) == ["third", "first", "second"])
        #expect(result.slides.map(\.position) == [3, 1, 2])
    }

    @Test
    func testMalformedSlideContentEntryIsDroppedOnItsOwn() throws {
        let entry = """
        {"slideId": "a", "position": 1, "contents": [
            {"key": "image", "value": "https://cdn.example/a.png", "type": "image"},
            "not an object",
            {"key": "headline", "value": "Hi", "type": "text"}
        ], "tracking": "nope"}
        """
        let result = try creative(contents: slides([entry]))
        #expect(result.slides.count == 1)
        #expect(result.slides.first?.contents.map(\.key) == ["image", "headline"])
        #expect(result.slides.first?.tracking == nil, "a malformed tracking block is absent, not a failure")
    }

    @Test
    func testSlidesEntryStaysInContents() throws {
        let result = try creative(contents: slides([slide("a", 1)]))
        #expect(result.contents.getContent(key: "slides") != nil)
        #expect(result.slides.count == 1)
    }

    @Test
    func testNonCarouselCreativeHasNoSlides() throws {
        let plain = try creative(contents: #"[{"key": "headline", "value": "Hi", "type": "text"}]"#)
        #expect(plain.slides.isEmpty)
        let malformed = try creative(contents: #"[{"key": "slides", "type": "slides", "value": "nope"}]"#)
        #expect(malformed.slides.isEmpty, "a slides entry that is not a list yields no slides and no failure")
    }

    @Test
    func testStandardFormatVersionAcceptsANumberAndNothingElse() throws {
        func version(_ literal: String) throws -> Int? {
            try creative(
                contents: "[]",
                metadata: #"{"effectiveStandardFormatVersion": \#(literal)}"#
            ).metadata?.effectiveStandardFormatVersion
        }
        #expect(try version("1") == 1)
        #expect(try version("1.0") == 1)
        #expect(try version(#""1""#) == nil)
        #expect(try version("1.5") == nil)
        #expect(try version("null") == nil)
    }

    @Test
    func testTemplateSourceIsOpenSetAndWrongTypesAreAbsent() throws {
        let known = try creative(contents: "[]", metadata: #"{"templateSource": "based_on_standard"}"#)
        #expect(known.metadata?.templateSource == "based_on_standard")
        let future = try creative(contents: "[]", metadata: #"{"templateSource": "from_the_future"}"#)
        #expect(future.metadata?.templateSource == "from_the_future", "an unknown value is kept verbatim")
        let mistyped = try creative(
            contents: "[]",
            metadata: #"{"templateSource": 3, "effectiveStandardFormatKey": false}"#
        )
        #expect(mistyped.metadata?.templateSource == nil)
        #expect(mistyped.metadata?.effectiveStandardFormatKey == nil)
    }

    @Test
    func testAssetContextComesFromTheGoldenFilesAndIsAbsentOtherwise() throws {
        func served(_ golden: String) throws -> Creative {
            let file = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Tools/JourneyE2E/fixtures/golden-wire/\(golden).json")
            let envelope = try JSONDecoder().decode(
                APIResponseBody<DecisionResponse>.self, from: Data(contentsOf: file)
            )
            return try #require(envelope.data?.first?.creatives?.first)
        }
        #expect(try served("branded_assets.full").metadata?.assetContext == "vehicle_marker")
        #expect(try served("card.minimal").metadata?.assetContext == nil)
        let mistyped = try creative(contents: "[]", metadata: #"{"assetContext": 3}"#)
        #expect(mistyped.metadata?.assetContext == nil, "a wrong type is absent, never a throw")
    }
}
