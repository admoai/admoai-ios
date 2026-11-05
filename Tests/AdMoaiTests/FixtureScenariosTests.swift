@testable import AdMoai
import Foundation
import Testing

// Shared fixture scenarios (@admoai/sdk-scenarios schemaVersion 2, admoai/adhub#4734)
//
// Feature: A publisher's app reads the standard native formats from a decision response
//   As a publisher's tech team
//   I want the SDK to decode the engine's golden wire files for every standard format
//   So that what my app reads (format, version, template source, contents, slides, trackers)
//   is exactly what the platform promises, in this SDK and in the other two
//
// The scenarios are DATA: `fixtureScenarios` in `Tools/JourneyE2E/scenarios.json`, vendored from
// adhub with the golden decision-wire files they decode. This file is only the interpreter, and
// it is strict in one direction: a manifest key it does not know FAILS, so a newer manifest can
// never pass silently on an SDK that cannot check it.

// MARK: - Loading

private let toolsDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // AdMoaiTests
    .deletingLastPathComponent() // Tests
    .deletingLastPathComponent() // repo root
    .appendingPathComponent("Tools/JourneyE2E")

/// One fixture scenario, carried as serialized JSON so the argument is `Sendable` and each
/// F-id reports on its own. `loadError` turns an unreadable manifest into a failing test instead
/// of a parameterized test with zero arguments, which would pass.
struct FixtureScenario: Sendable, CustomTestStringConvertible {
    let id: String
    let title: String
    let json: Data
    let loadError: String?

    var testDescription: String {
        "\(id) \(title)"
    }

    static let all: [FixtureScenario] = {
        do {
            let data = try Data(contentsOf: toolsDirectory.appendingPathComponent("scenarios.json"))
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = root["fixtureScenarios"] as? [[String: Any]], !entries.isEmpty
            else { return [failure("the manifest has no fixtureScenarios")] }
            return try entries.map { entry in
                try FixtureScenario(
                    id: (entry["id"] as? String) ?? "?",
                    title: (entry["title"] as? String) ?? "",
                    json: JSONSerialization.data(withJSONObject: entry),
                    loadError: nil
                )
            }
        } catch {
            return [failure("scenarios.json cannot be read: \(error)")]
        }
    }()

    private static func failure(_ message: String) -> FixtureScenario {
        FixtureScenario(id: "LOAD", title: "the fixture scenarios load", json: Data(), loadError: message)
    }
}

// MARK: - Edits

private struct FixtureEditError: Error, CustomStringConvertible {
    let description: String
}

private typealias JSONObject = [String: Any]

/// Applies `fixture.edits` in order. `at` names which object(s) of the decision wire change:
/// the response root, the first creative, its `metadata`, every element of its `contents`, or
/// every element of the `value` array of the content entry keyed `slides`.
private func applyEdits(_ edits: [JSONObject], to root: inout JSONObject) throws {
    for edit in edits {
        let change = try makeChange(edit)
        let target = edit["at"] as? String
        if target == "response" {
            change(&root)
            continue
        }
        try editCreative(in: &root) { creative in
            switch target {
            case "creative":
                change(&creative)
            case "metadata":
                var metadata = creative["metadata"] as? JSONObject ?? [:]
                change(&metadata)
                creative["metadata"] = metadata
            case "content":
                let contents = creative["contents"] as? [JSONObject] ?? []
                creative["contents"] = contents.map { entry -> JSONObject in
                    var entry = entry
                    change(&entry)
                    return entry
                }
            case "slide":
                var contents = creative["contents"] as? [JSONObject] ?? []
                guard let index = contents.firstIndex(where: { $0["key"] as? String == "slides" }) else {
                    throw FixtureEditError(description: "edit at slide: the creative has no slides entry")
                }
                let slides = contents[index]["value"] as? [JSONObject] ?? []
                contents[index]["value"] = slides.map { slide -> JSONObject in
                    var slide = slide
                    change(&slide)
                    return slide
                }
                creative["contents"] = contents
            default:
                throw FixtureEditError(description: "unknown edit target at=\(target ?? "nil")")
            }
        }
    }
}

private func makeChange(_ edit: JSONObject) throws -> (inout JSONObject) -> Void {
    if let key = edit["remove"] as? String {
        return { $0.removeValue(forKey: key) }
    }
    if let key = edit["add"] as? String {
        let value = edit["value"] ?? NSNull()
        return { $0[key] = value }
    }
    throw FixtureEditError(description: "an edit with neither remove nor add: \(edit)")
}

/// `data[0].creatives[0]`, the creative every fixture scenario is about.
private func editCreative(in root: inout JSONObject, _ body: (inout JSONObject) throws -> Void) throws {
    guard var data = root["data"] as? [JSONObject], !data.isEmpty,
          var creatives = data[0]["creatives"] as? [JSONObject], !creatives.isEmpty
    else { throw FixtureEditError(description: "the golden file has no data[0].creatives[0]") }
    try body(&creatives[0])
    data[0]["creatives"] = creatives
    root["data"] = data
}

// MARK: - The interpreter

private let metadataKeys = ["effectiveStandardFormatKey", "effectiveStandardFormatVersion", "templateSource"]

struct FixtureScenariosTests {
    @Test(arguments: FixtureScenario.all)
    func testFixtureScenario(_ scenario: FixtureScenario) throws {
        if let loadError = scenario.loadError {
            Issue.record("\(loadError)")
            return
        }
        let entry = try #require(try JSONSerialization.jsonObject(with: scenario.json) as? JSONObject)
        let fixture = try #require(entry["fixture"] as? JSONObject)
        let golden = try #require(fixture["golden"] as? String)
        let expect = try #require(entry["expect"] as? JSONObject)

        // The wire, as the golden file has it, then edited.
        let file = toolsDirectory.appendingPathComponent("fixtures/golden-wire/\(golden).json")
        var wire = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? JSONObject,
            "\(golden).json is a JSON object"
        )
        do {
            try applyEdits(fixture["edits"] as? [JSONObject] ?? [], to: &wire)
        } catch {
            Issue.record("\(scenario.id): \(error)")
            return
        }

        // Decoded exactly as APIClient decodes a 200: the tolerant envelope, no custom decoder.
        let body = try JSONSerialization.data(withJSONObject: wire)
        let creative: Creative
        do {
            let envelope = try JSONDecoder().decode(APIResponseBody<DecisionResponse>.self, from: body)
            let creatives = envelope.data?.first?.creatives ?? []
            #expect(creatives.count == 1, "\(scenario.id): exactly one creative")
            guard let first = creatives.first else { return }
            creative = first
        } catch {
            Issue.record("\(scenario.id): decoding threw \(error)")
            return
        }

        for (key, value) in expect {
            check(scenario.id, key, value, creative)
        }
    }

    private func check(_ id: String, _ key: String, _ value: Any, _ creative: Creative) {
        switch key {
        case "decodes":
            #expect(value as? Bool == true, "\(id): decodes is true")
        case "metadata":
            checkMetadata(id, value as? JSONObject, creative.metadata)
        case "templateKey":
            #expect(creative.template?.key == value as? String, "\(id): templateKey")
        case "contentKeys":
            let plain = Set(creative.contents.map(\.key)).subtracting(["slides", MatchedPointsEntry.contentKey])
            #expect(plain == Set(strings(value)), "\(id): contentKeys, got \(plain.sorted())")
        case "contentKeysAbsent":
            for absent in strings(value) {
                #expect(creative.contents.getContent(key: absent) == nil, "\(id): \(absent) is absent")
            }
        case "clickKeys":
            #expect((creative.tracking.clicks ?? []).map(\.key) == strings(value), "\(id): clickKeys")
        case "customKeys":
            #expect((creative.tracking.custom ?? []).map(\.key) == strings(value), "\(id): customKeys")
        case "videoEventKeys":
            #expect((creative.tracking.videoEvents ?? []).map(\.key) == strings(value), "\(id): videoEventKeys")
        case "slides":
            checkSlides(id, value as? [JSONObject] ?? [], creative.slides)
        case "noSkippableSetting":
            #expect(value as? Bool == true, "\(id): noSkippableSetting is true")
            #expect(creative.metadata?.isSkippable == nil, "\(id): isSkippable is absent")
            #expect(creative.metadata?.skipOffsetSeconds == nil, "\(id): skipOffsetSeconds is absent")
        case "matchedPoints":
            #expect(creative.matchedPoints.count == value as? Int, "\(id): matchedPoints count")
        default:
            Issue.record("\(id): unknown expect key \(key)")
        }
    }

    private func checkMetadata(_ id: String, _ expected: JSONObject?, _ metadata: Metadata?) {
        guard let expected else {
            Issue.record("\(id): metadata expectation is not an object")
            return
        }
        for (key, value) in expected {
            switch key {
            case "effectiveStandardFormatKey":
                expectOptional(id, key, metadata?.effectiveStandardFormatKey, value)
            case "effectiveStandardFormatVersion":
                expectOptional(id, key, metadata?.effectiveStandardFormatVersion, value)
            case "templateSource":
                expectOptional(id, key, metadata?.templateSource, value)
            default:
                Issue.record("\(id): unknown metadata expect key \(key) (known: \(metadataKeys))")
            }
        }
    }

    /// JSON null expects the property to be `nil`; anything else must equal it.
    private func expectOptional<T: Equatable>(_ id: String, _ key: String, _ actual: T?, _ expected: Any) {
        if expected is NSNull {
            #expect(actual == nil, "\(id): metadata.\(key) is absent, got \(String(describing: actual))")
        } else if let typed = expected as? T {
            #expect(actual == typed, "\(id): metadata.\(key), got \(String(describing: actual))")
        } else {
            Issue.record("\(id): metadata.\(key) expectation \(expected) has the wrong type")
        }
    }

    private func checkSlides(_ id: String, _ expected: [JSONObject], _ slides: [Slide]) {
        #expect(slides.count == expected.count, "\(id): slide count, got \(slides.count)")
        for (index, want) in expected.enumerated() where index < slides.count {
            let slide = slides[index]
            let label = "\(id): slide \(index + 1)"
            for key in want.keys where !["slideId", "position", "contentKeys", "viewKeys", "clickKeys"].contains(key) {
                Issue.record("\(label): unknown slide expect key \(key)")
            }
            #expect(slide.slideId == want["slideId"] as? String, "\(label) slideId")
            #expect(slide.position == want["position"] as? Int, "\(label) position")
            #expect(Set(slide.contents.map(\.key)) == Set(strings(want["contentKeys"])), "\(label) contentKeys")
            #expect(
                Set((slide.tracking?.views ?? []).map(\.key)) == Set(strings(want["viewKeys"])),
                "\(label) viewKeys"
            )
            #expect(
                Set((slide.tracking?.clicks ?? []).map(\.key)) == Set(strings(want["clickKeys"])),
                "\(label) clickKeys"
            )
        }
    }

    private func strings(_ value: Any?) -> [String] {
        value as? [String] ?? []
    }
}
