import Foundation
import Testing

@testable import AdMoai

// Journey Takeover Ads — read-only response metadata (creative.journey)
//
// Feature: Parse read-only Journey metadata without owning Journey state
//   As a publisher SDK
//   I want to parse the nested creative.journey object tolerantly
//   So that Journey serves surface engine-owned metadata while normal ads and
//   future engine versions never break decoding
//
// The engine emits creative.journey as a NESTED object with exact camelCase keys.

private func decodeCreative(_ json: String) throws -> Creative {
    try JSONDecoder().decode(Creative.self, from: json.data(using: .utf8)!)
}

private let journeyCreativeJSON = """
{
    "contents": [{"key": "title", "value": "Hello", "type": "string"}],
    "advertiser": {"id": "adv1", "name": "Acme"},
    "template": {"key": "standard"},
    "tracking": {"impressions": [{"key": "default", "url": "https://track/imp"}]},
    "metadata": {"adId": "ad1", "creativeId": "cr1", "templateId": "tpl1", "placementId": "pl1", "priority": "standard"},
    "journey": {
        "dealId": "deal_123",
        "instanceId": "inst_456",
        "definitionKey": "summer_campaign",
        "stageId": "stage_1",
        "stageKey": "pre_ride",
        "stageNodeId": "node_9",
        "sessionId": "trip-abc",
        "optStatus": "in",
        "isCompletion": false,
        "pricingModel": "cpt",
        "fallbackBillingMode": "bill_per_stage"
    }
}
"""

struct JourneyResponseTests {

    // Scenario: a Journey serve exposes every engine key on creative.journey
    @Test
    func testExactKeyParse() throws {
        let creative = try decodeCreative(journeyCreativeJSON)
        #expect(creative.isJourneyAd)
        let j = try #require(creative.journey)
        #expect(j.dealId == "deal_123")
        #expect(j.instanceId == "inst_456")
        #expect(j.definitionKey == "summer_campaign")
        #expect(j.stageId == "stage_1")
        #expect(j.stageKey == "pre_ride")
        #expect(j.stageNodeId == "node_9")
        #expect(j.sessionId == "trip-abc")
        #expect(j.optStatus == .optIn)
        #expect(j.isCompletion == false)
        #expect(j.pricingModel == "cpt")
        #expect(j.fallbackBillingMode == "bill_per_stage")
    }

    // Scenario: the JourneyHelper getters mirror the nested fields
    @Test
    func testJourneyHelperGetters() throws {
        let creative = try decodeCreative(journeyCreativeJSON)
        #expect(creative.journeyDealId == "deal_123")
        #expect(creative.journeyInstanceId == "inst_456")
        #expect(creative.journeyStageKey == "pre_ride")
        #expect(creative.journeyOptStatus == .optIn)
        #expect(creative.journeyPricingModel == "cpt")
        #expect(creative.isJourneyCompletion == false)
    }

    // Scenario: optStatus in/out both parse
    @Test
    func testOptStatusInOut() throws {
        let out = try decodeCreative(journeyCreativeJSON.replacingOccurrences(of: "\"optStatus\": \"in\"", with: "\"optStatus\": \"out\""))
        #expect(out.journey?.optStatus == .optOut)
    }

    // Scenario: a normal ad (no journey) decodes with journey == nil (backward compatible)
    @Test
    func testBackwardCompatNoJourney() throws {
        let json = """
        {
            "contents": [{"key": "title", "value": "Hi", "type": "string"}],
            "advertiser": {"id": "adv1"},
            "tracking": {},
            "metadata": {"adId": "a", "creativeId": "c", "templateId": "t", "placementId": "p", "priority": "standard"}
        }
        """
        let creative = try decodeCreative(json)
        #expect(creative.journey == nil)
        #expect(creative.isJourneyAd == false)
    }

    // Scenario: a final_stage completion serve
    @Test
    func testFinalStageCompletion() throws {
        let json = journeyCreativeJSON.replacingOccurrences(of: "\"isCompletion\": false", with: "\"isCompletion\": true")
        let creative = try decodeCreative(json)
        #expect(creative.isJourneyCompletion == true)
    }

    // MARK: - Tolerant Reader (forward-compat)

    // Scenario: unknown fields and unknown optStatus are ignored, never throw
    @Test
    func testForwardCompatUnknownFieldsAndEnum() throws {
        let json = """
        {
            "contents": [{"key": "title", "value": "Hi", "type": "string"}],
            "advertiser": {"id": "adv1"},
            "tracking": {},
            "metadata": {"adId": "a", "creativeId": "c", "templateId": "t", "placementId": "p", "priority": "standard"},
            "brandNewTopLevelField": 123,
            "journey": {
                "dealId": "deal_9",
                "optStatus": "paused",
                "someFutureKey": {"nested": true},
                "pricingModel": "brand_new_model"
            }
        }
        """
        let creative = try decodeCreative(json)
        let j = try #require(creative.journey)
        #expect(j.dealId == "deal_9")
        #expect(j.optStatus == nil)               // unknown enum -> nil (open set)
        #expect(j.pricingModel == "brand_new_model")  // open-set string preserved
        #expect(j.isCompletion == nil)            // omitted optional
    }

    // Scenario: retyped Journey fields degrade to nil instead of throwing
    @Test
    func testForwardCompatRetypedFields() throws {
        let json = """
        {
            "contents": [{"key": "title", "value": "Hi", "type": "string"}],
            "advertiser": {"id": "adv1"},
            "tracking": {},
            "metadata": {"adId": "a", "creativeId": "c", "templateId": "t", "placementId": "p", "priority": "standard"},
            "journey": {
                "dealId": 12345,
                "instanceId": "inst_1",
                "isCompletion": "yes",
                "optStatus": true
            }
        }
        """
        let creative = try decodeCreative(json)
        let j = try #require(creative.journey)
        #expect(j.dealId == nil)          // number where a string was expected -> nil (NOT a throw)
        #expect(j.instanceId == "inst_1") // sibling field still reads
        #expect(j.isCompletion == nil)    // "yes" is not a Bool -> nil
        #expect(j.optStatus == nil)       // true is not an opt literal -> nil
    }

    // Scenario: a non-object journey value is ignored (whole response still decodes)
    @Test
    func testNonObjectJourneyIgnored() throws {
        let json = """
        {
            "contents": [{"key": "title", "value": "Hi", "type": "string"}],
            "advertiser": {"id": "adv1"},
            "tracking": {},
            "metadata": {"adId": "a", "creativeId": "c", "templateId": "t", "placementId": "p", "priority": "standard"},
            "journey": 42
        }
        """
        let creative = try decodeCreative(json)
        #expect(creative.journey == nil)
        #expect(creative.isJourneyAd == false)
    }

    // Scenario: object content entries are preserved (degraded); non-object entries dropped
    //   A retyped `type` must NOT discard a content whose key+value are still usable.
    @Test
    func testTolerantContentDecoding() throws {
        let json = """
        {
            "contents": [
                {"key": "title", "value": "Good", "type": "string"},
                {"key": "subtitle", "value": "Keep me", "type": 123},
                42
            ],
            "advertiser": {"id": "adv1"},
            "tracking": {},
            "metadata": {"adId": "a", "creativeId": "c", "templateId": "t", "placementId": "p", "priority": "standard"},
            "journey": {"dealId": "d1", "optStatus": "in"}
        }
        """
        let creative = try decodeCreative(json)
        // The non-object (42) is dropped; both object entries survive.
        #expect(creative.contents.count == 2)
        let subtitle = creative.contents.getContent(key: "subtitle")
        #expect(subtitle?.value.value as? String == "Keep me")  // value preserved despite bad type
        #expect(subtitle?.type == "")                            // retyped type degrades to ""
        #expect(creative.journey?.dealId == "d1")
    }

    // Scenario: a content entry missing `value` entirely is preserved (value degrades to null),
    //           not dropped — and reads back as nil for any typed cast
    @Test
    func testContentMissingValuePreserved() throws {
        let json = """
        {
            "contents": [{"key": "novalue"}],
            "advertiser": {"id": "adv1"},
            "tracking": {},
            "metadata": {"adId": "a", "creativeId": "c", "templateId": "t", "placementId": "p", "priority": "standard"}
        }
        """
        let creative = try decodeCreative(json)
        #expect(creative.contents.count == 1)
        let content = creative.contents.getContent(key: "novalue")
        #expect(content?.type == "")
        #expect(content?.value.value as? String == nil)  // null value -> nil for any typed cast
    }

    // Scenario: a full DecisionResponse array with a Journey creative decodes end-to-end
    @Test
    func testFullDecisionResponseWithJourney() throws {
        let json = """
        [
            {
                "placement": "home",
                "creatives": [\(journeyCreativeJSON)]
            }
        ]
        """
        let response = try JSONDecoder().decode(DecisionResponse.self, from: json.data(using: .utf8)!)
        #expect(response.count == 1)
        #expect(response.first?.placement == "home")
        #expect(response.first?.creatives?.first?.journey?.instanceId == "inst_456")
    }
}
