import Foundation
import Testing

@testable import AdMoai

// Journey Takeover Ads — request context (sessionId, journeyOpt)
//
// Feature: Forward publisher Journey context to the decision-engine
//   As a publisher SDK
//   I want to forward `sessionId` and `journeyOpt` verbatim as top-level request fields
//   So that the engine can run Journey eligibility without the SDK owning any Journey state
//
// The engine is the source of truth: `sessionId` is trimmed and silently disables Journey
// when blank / over 256 UTF-8 bytes; `journeyOpt` is strictly "in"/"out" or the whole
// request is rejected with HTTP 400.

private let baseURL = "https://api.mock.admoai.com"
// Journey usage realistically sets apiVersion; using it here also avoids the (correct)
// "Journey context set without apiVersion" build() warning noise in serialization tests.
// apiVersion affects only the request header, not the encoded body these tests assert.
private let journeyConfig = SDKConfig(baseUrl: baseURL, apiVersion: "2025-11-01")

private func encodedJSON(_ request: DecisionRequest) throws -> String {
    let data = try JSONEncoder().encode(request)
    return String(data: data, encoding: .utf8)!
}

struct JourneyRequestTests {

    // Scenario: sessionId and journeyOpt serialize as top-level camelCase keys
    //   Given a builder with a sessionId and journeyOpt=in
    //   When the request is encoded
    //   Then the body carries top-level "sessionId" and "journeyOpt":"in"
    @Test
    func testSessionIdAndJourneyOptSerialization() throws {
        let sdk = AdMoai(config: journeyConfig)
        let request = sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .setSessionId("trip-abc-123")
            .setJourneyOpt(.optIn)
            .build()

        #expect(request.sessionId == "trip-abc-123")
        #expect(request.journeyOpt == .optIn)

        let json = try encodedJSON(request)
        #expect(json.contains("\"sessionId\":\"trip-abc-123\""))
        #expect(json.contains("\"journeyOpt\":\"in\""))
    }

    // Scenario: journeyOpt emits only the wire literals "in"/"out"
    @Test
    func testJourneyOptWireLiterals() throws {
        let sdk = AdMoai(config: journeyConfig)

        let optIn = try encodedJSON(
            sdk.createRequestBuilder().addPlacement(key: "home").setJourneyOpt(.optIn).build())
        #expect(optIn.contains("\"journeyOpt\":\"in\""))

        let optOut = try encodedJSON(
            sdk.createRequestBuilder().addPlacement(key: "home").setJourneyOpt(.optOut).build())
        #expect(optOut.contains("\"journeyOpt\":\"out\""))

        #expect(JourneyOpt.optIn.rawValue == "in")
        #expect(JourneyOpt.optOut.rawValue == "out")
    }

    // Scenario: a blank sessionId is omitted from the wire (engine would silently disable Journey)
    @Test
    func testBlankSessionIdOmitted() throws {
        let sdk = AdMoai(config: journeyConfig)
        let request = sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .setSessionId("   ")
            .build()

        let json = try encodedJSON(request)
        #expect(!json.contains("\"sessionId\""))
    }

    // Scenario: a sessionId is trimmed on the wire
    @Test
    func testSessionIdTrimmedOnWire() throws {
        let sdk = AdMoai(config: journeyConfig)
        let request = sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .setSessionId("  trip-xyz  ")
            .build()

        let json = try encodedJSON(request)
        #expect(json.contains("\"sessionId\":\"trip-xyz\""))
    }

    // Scenario: an over-length sessionId is sent as-is (engine silently disables Journey,
    //           the request still succeeds as a normal ad)
    @Test
    func testOverLengthSessionIdSentAsIs() throws {
        let sdk = AdMoai(config: journeyConfig)
        let longId = String(repeating: "a", count: 300)  // 300 bytes > 256
        let request = sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .setSessionId(longId)
            .build()

        let json = try encodedJSON(request)
        #expect(json.contains("\"sessionId\":\"\(longId)\""))
    }

    // MARK: - PII-safe rejection reason (byte-length, never the value)

    // Scenario: reason token is nil for a valid sessionId
    @Test
    func testRejectionReasonNilForValid() {
        #expect(DecisionRequest.journeySessionIdRejectionReason("trip-1") == nil)
        #expect(DecisionRequest.journeySessionIdRejectionReason(nil) == nil)
    }

    // Scenario: blank-after-trim reason
    @Test
    func testRejectionReasonBlank() {
        #expect(DecisionRequest.journeySessionIdRejectionReason("") == "blank_after_trim")
        #expect(DecisionRequest.journeySessionIdRejectionReason("   \n ") == "blank_after_trim")
    }

    // Scenario: over-256-BYTES reason, using multi-byte emoji to prove byte (not rune) counting
    @Test
    func testRejectionReasonExceedsBytesMultiByte() {
        // 65 × 4-byte emoji = 260 bytes, but only 65 characters (< 256 runes)
        let emoji = String(repeating: "😀", count: 65)
        #expect(emoji.count < 256)
        #expect(emoji.utf8.count == 260)
        #expect(DecisionRequest.journeySessionIdRejectionReason(emoji) == "exceeds_256_bytes")

        // Exactly 256 bytes is accepted (boundary)
        let exact = String(repeating: "a", count: 256)
        #expect(DecisionRequest.journeySessionIdRejectionReason(exact) == nil)
        // 257 bytes rejected
        #expect(DecisionRequest.journeySessionIdRejectionReason(String(repeating: "a", count: 257)) == "exceeds_256_bytes")
    }

    // MARK: - Sticky sessionId semantics

    // Scenario: the sticky sessionId is inherited by every builder and sent on each request
    @Test
    func testStickySessionIdInherited() throws {
        let sdk = AdMoai(config: journeyConfig, sessionId: "sticky-1")
        #expect(sdk.sessionId == "sticky-1")

        let r1 = sdk.createRequestBuilder().addPlacement(key: "a").build()
        let r2 = sdk.createRequestBuilder().addPlacement(key: "b").build()
        #expect(r1.sessionId == "sticky-1")
        #expect(r2.sessionId == "sticky-1")
    }

    // Scenario: init(sessionId:) normalizes to wire form (trim; blank → nil)
    @Test
    func testInitSessionIdNormalized() {
        #expect(AdMoai(config: journeyConfig, sessionId: "  s  ").sessionId == "s")
        #expect(AdMoai(config: journeyConfig, sessionId: "   ").sessionId == nil)
        #expect(AdMoai(config: journeyConfig).sessionId == nil)
    }

    // Scenario: a per-request setSessionId overrides the sticky default
    @Test
    func testPerRequestOverride() throws {
        let sdk = AdMoai(config: journeyConfig, sessionId: "sticky-1")
        let request = sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .setSessionId("override-2")
            .build()
        #expect(request.sessionId == "override-2")
    }

    // Scenario: builder.setSessionId stores the wire form (trimmed; blank -> nil) so
    //           request.sessionId matches exactly what is sent
    @Test
    func testBuilderSetSessionIdNormalizesToWireForm() {
        let sdk = AdMoai(config: journeyConfig)
        let padded = sdk.createRequestBuilder().addPlacement(key: "home").setSessionId("  abc  ").build()
        #expect(padded.sessionId == "abc")   // property matches the trimmed wire value

        let blank = sdk.createRequestBuilder().addPlacement(key: "home").setSessionId("   ").build()
        #expect(blank.sessionId == nil)       // blank collapses to nil, matching omission on the wire
    }

    // Scenario: rotating the sticky sessionId affects only subsequently-created builders
    @Test
    func testRotationViaSetSessionId() throws {
        var sdk = AdMoai(config: journeyConfig, sessionId: "session-old")
        let before = sdk.createRequestBuilder().addPlacement(key: "a").build()
        sdk.setSessionId("session-new")
        let after = sdk.createRequestBuilder().addPlacement(key: "b").build()

        #expect(before.sessionId == "session-old")
        #expect(after.sessionId == "session-new")
        #expect(sdk.sessionId == "session-new")

        sdk.clearSessionId()
        #expect(sdk.sessionId == nil)
        #expect(sdk.createRequestBuilder().addPlacement(key: "c").build().sessionId == nil)
    }

    // MARK: - clearAll asymmetry

    // Scenario: clearAll clears journeyOpt but preserves the sticky sessionId
    @Test
    func testClearAllClearsJourneyOptPreservesSessionId() throws {
        let sdk = AdMoai(config: journeyConfig, sessionId: "sticky-keep")
        let request = sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .setJourneyOpt(.optOut)
            .clearAll()
            .addPlacement(key: "home")
            .build()

        #expect(request.journeyOpt == nil)       // per-request control cleared
        #expect(request.sessionId == "sticky-keep")  // sticky session preserved
    }

    // MARK: - Backward compatibility

    // Scenario: a request with no Journey fields is byte-identical to v1.4.0 behavior
    //   Given a builder with no Journey context
    //   When the request is encoded
    //   Then the body carries neither "sessionId" nor "journeyOpt"
    @Test
    func testNoJourneyFieldsBackwardCompatible() throws {
        let sdk = AdMoai(config: journeyConfig)
        let request = sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .setUserId("user-1")
            .build()

        #expect(request.sessionId == nil)
        #expect(request.journeyOpt == nil)

        let json = try encodedJSON(request)
        #expect(!json.contains("\"sessionId\""))
        #expect(!json.contains("\"journeyOpt\""))
    }
}
