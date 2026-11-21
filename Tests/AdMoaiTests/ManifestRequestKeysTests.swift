import AdMoai
import Foundation
import ManifestExpectations
import Testing

struct ManifestRequestKeysTests {
    @Test
    func testKnownRequestKeysPass() {
        let request: [String: Any] = [
            "placements": [], "custom": [], "session": "x", "journeyOpt": "in",
            "apiVersion": "none", "distance": [:], "device": [:],
        ]
        #expect(ManifestRequestKeys.unknownRequestKeys(in: request).isEmpty)
        #expect(ManifestRequestKeys.unknownDeviceKeys(in: ["carrier": "x", "category": "phone"]).isEmpty)
    }

    @Test
    func testUnknownRequestKeyIsReported() {
        let request: [String: Any] = ["placements": [], "zeta": 1, "alpha": 2]
        #expect(ManifestRequestKeys.unknownRequestKeys(in: request) == ["alpha", "zeta"])
    }

    @Test
    func testUnknownDeviceKeyIsReported() {
        #expect(ManifestRequestKeys.unknownDeviceKeys(in: ["carrier": "x", "model": "y"]) == ["model"])
    }

    @Test
    func testInteractiveExperienceKeysAreRecognisedAndUnknownOnesReported() {
        #expect(ManifestRequestKeys.request.contains("interactiveExperience"))
        #expect(ManifestRequestKeys.unknownInteractiveExperienceKeys(
            in: ["supported": true, "availableAttributeKeys": [], "zeta": 1]
        ) == ["zeta"])
    }

    @Test
    func testInteractiveExperienceRefusalWhenNotASupportDeclaration() {
        #expect(ManifestRequestKeys.interactiveExperienceRefusal(
            in: ["supported": false, "availableAttributeKeys": ["email"]]
        ) != nil)
        #expect(ManifestRequestKeys.interactiveExperienceRefusal(in: ["availableAttributeKeys": []]) != nil)
        #expect(ManifestRequestKeys.interactiveExperienceRefusal(
            in: ["supported": true, "availableAttributeKeys": ["email", "homeAddress"]]
        ) != nil)
        #expect(ManifestRequestKeys.interactiveExperienceRefusal(
            in: ["supported": true, "availableAttributeKeys": ["fullName", "email", "phone"]]
        ) == nil)
        #expect(ManifestRequestKeys.interactiveExperienceRefusal(
            in: ["supported": true, "availableAttributeKeys": []]
        ) == nil)
    }

    @Test
    func testDeviceCategoryAllowlistIsExact() {
        // Pinned to the SDK's own enum, so a new DeviceCategory case cannot leave the runner behind.
        #expect(ManifestRequestKeys.deviceCategories == Set(DeviceCategory.allCases.map(\.rawValue)))
    }

    private struct Holder: Decodable { let value: ManifestCustomValue }

    private func decode(_ json: String) throws -> ManifestCustomValue {
        try JSONDecoder().decode(Holder.self, from: Data("{\"value\":\(json)}".utf8)).value
    }

    @Test
    func testCustomValueDecodesStringAndList() throws {
        #expect(try decode("\"x\"") == .string("x"))
        #expect(try decode("[\"a\",\"b\"]") == .strings(["a", "b"]))
    }

    @Test
    func testCustomValueRejectsOtherShapes() {
        #expect(throws: DecodingError.self) { try decode("1") }
        #expect(throws: DecodingError.self) { try decode("{\"a\":1}") }
    }
}
