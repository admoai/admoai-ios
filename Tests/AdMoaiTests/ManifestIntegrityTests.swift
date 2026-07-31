import CryptoKit
import Foundation
import Testing

/// The shared cross-SDK E2E scenario manifest is mirrored byte-identically into all three SDK
/// repos. This pins its SHA-256 so an edit to one copy fails that repo's build until the constant
/// is updated — and because the SAME constant appears in all three repos, three matching hashes is
/// mechanical proof the copies agree. Divergence is otherwise invisible: it was exactly how the
/// hand-written suites drifted (Android's K1 asserted less than iOS's and Flutter's).
///
/// If this fails after you intentionally changed the manifest: update the copy in ALL THREE repos,
/// then update this constant in all three. Cross-repo enforcement in CI belongs in adhub, which is
/// the only place that can see all three at once.
struct ManifestIntegrityTests {

    private static let expectedSHA256 =
        "5b7c2b3d261d68b5b4e52091d0b00ac7ec1bd09cf950f482ce968e1e1a34d2ca"

    private func manifestURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // AdMoaiTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Tools/JourneyE2E/scenarios.json")
    }

    @Test
    func testManifestMatchesTheCrossSDKHash() throws {
        let data = try Data(contentsOf: manifestURL())
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        // On failure the digest is printed by the expectation itself; the fix is in this file's
        // doc comment.
        #expect(digest == Self.expectedSHA256)
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
