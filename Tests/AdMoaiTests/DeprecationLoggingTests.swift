import Foundation
import Testing

@testable import AdMoai

// API deprecation-aware logging
//
// Feature: Warn once when the engine flags the negotiated API version as deprecated
//   As a publisher SDK
//   I want to surface an X-API-Deprecated response header as a log warning
//   So that publishers learn to update SDKConfig.apiVersion before it is removed
//
// The engine sets `X-API-Deprecated: true` (and optionally a Sunset date). The SDK inspects
// decision responses in both DEBUG and release builds; tracking is fire-and-forget and does
// not inspect headers (documented limitation).

struct DeprecationLoggingTests {

    // Scenario: no deprecation header -> no warning
    @Test
    func testNotDeprecatedWhenHeaderAbsentOrFalse() {
        #expect(AdMoaiClient.deprecationMessage(isDeprecated: nil, sunset: nil) == nil)
        #expect(AdMoaiClient.deprecationMessage(isDeprecated: "false", sunset: nil) == nil)
        #expect(AdMoaiClient.deprecationMessage(isDeprecated: "1", sunset: nil) == nil)
        #expect(AdMoaiClient.deprecationMessage(isDeprecated: "", sunset: "2026-01-01") == nil)
    }

    // Scenario: X-API-Deprecated: true -> a warning message (case-insensitive)
    @Test
    func testDeprecatedTrueProducesMessage() {
        let msg = AdMoaiClient.deprecationMessage(isDeprecated: "true", sunset: nil)
        #expect(msg != nil)
        #expect(msg?.contains("deprecated") == true)
        #expect(msg?.contains("apiVersion") == true)

        #expect(AdMoaiClient.deprecationMessage(isDeprecated: "TRUE", sunset: nil) != nil)
        #expect(AdMoaiClient.deprecationMessage(isDeprecated: "True", sunset: nil) != nil)
    }

    // Scenario: a Sunset date is surfaced in the warning
    @Test
    func testSunsetDateIncluded() {
        let msg = AdMoaiClient.deprecationMessage(isDeprecated: "true", sunset: "2026-06-01")
        #expect(msg?.contains("2026-06-01") == true)

        // Empty sunset is treated as absent (no date fragment)
        let noDate = AdMoaiClient.deprecationMessage(isDeprecated: "true", sunset: "")
        #expect(noDate != nil)
        #expect(noDate?.contains("sunset") == false)
    }
}
