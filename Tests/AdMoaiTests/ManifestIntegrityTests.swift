import Foundation
import Testing

/// The shared cross-SDK scenario manifest is vendored from adhub's `@admoai/sdk-scenarios`
/// package (admoai/adhub#4158). Which version, and that the bytes are exactly that version, is
/// CI's *Scenario manifest* job (`.github/scripts/scenarios.sh check`); it replaced the SHA-256
/// this file used to pin, so there is one pin, `Tools/JourneyE2E/MANIFEST_VERSION`, not two.
/// What stays here, offline, is the shape the runner relies on.
struct ManifestIntegrityTests {
    private func manifestURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AdMoaiTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Tools/JourneyE2E/scenarios.json")
    }

    @Test
    func testManifestIsStructurallyValid() throws {
        let data = try Data(contentsOf: manifestURL())
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let scenarios = try #require(root?["scenarios"] as? [[String: Any]])

        #expect(!scenarios.isEmpty, "the manifest declares at least one scenario")
        let ids = scenarios.compactMap { $0["id"] as? String }
        #expect(ids.count == scenarios.count, "every scenario has an id")
        #expect(Set(ids).count == ids.count, "scenario ids are unique")
        for entry in scenarios {
            #expect(!((entry["title"] as? String) ?? "").isEmpty, "every scenario has a title")
            #expect(entry["request"] is [String: Any], "every scenario has a request block")
            #expect(entry["expect"] is [String: Any], "every scenario has an expect block")
        }
    }
}
