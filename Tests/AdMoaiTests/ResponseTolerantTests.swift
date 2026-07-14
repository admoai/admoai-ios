import Foundation
import Testing

@testable import AdMoai

// Whole-response Tolerant Reader (PR B)
//
// Feature: The entire response decodes tolerantly
//   As a publisher SDK on any version
//   I want the whole response tree to survive additive/malformed engine payloads
//   So that a future engine version or a partially-malformed response never throws
//
// Non-breaking rule: currently non-optional fields default to ""/empty rather than widening
// to Optional. Lists drop malformed/non-object entries instead of failing the whole array.

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(type, from: json.data(using: .utf8)!)
}

struct ResponseTolerantTests {

    // Scenario: a fully future-version envelope decodes without throwing
    @Test
    func testFutureVersionEnvelopeDoesNotThrow() throws {
        let body = try decode(APIResponseBody<DecisionResponse>.self, """
        {
            "success": true,
            "data": [
                {
                    "placement": "home",
                    "creatives": [{
                        "contents": [{"key": "title", "value": "Hi", "type": "string"}],
                        "advertiser": {"id": "adv1", "unknownAdvField": 9},
                        "tracking": {},
                        "metadata": {"adId": "a", "creativeId": "c", "templateId": "t", "placementId": "p", "priority": "standard"},
                        "futureCreativeField": {"nested": true}
                    }],
                    "futureDecisionField": 42
                }
            ],
            "errors": [],
            "warnings": [],
            "brandNewTopLevelField": {"x": [1, 2, 3]}
        }
        """)
        #expect(body.success == true)
        #expect(body.data?.count == 1)
        #expect(body.data?.first?.hasCreative == true)
    }

    // Scenario: an alien/empty body decodes to success=false, data=nil (never throws)
    @Test
    func testAlienBodyDegradesGracefully() throws {
        let body = try decode(APIResponseBody<DecisionResponse>.self, #"{"totally": "unexpected"}"#)
        #expect(body.success == false)
        #expect(body.data == nil)
    }

    // Scenario: Metadata with missing id fields defaults to "" (non-breaking, never throws)
    @Test
    func testMetadataMissingIdsDefaultToEmpty() throws {
        let meta = try decode(Metadata.self, #"{"priority": "standard"}"#)
        #expect(meta.adId == "")
        #expect(meta.creativeId == "")
        #expect(meta.templateId == "")
        #expect(meta.placementId == "")
        #expect(meta.priority == .standard)
    }

    // Scenario: Metadata with retyped fields degrades, never throws
    @Test
    func testMetadataRetypedFieldsDegrade() throws {
        let meta = try decode(Metadata.self, """
        {"adId": 123, "creativeId": true, "templateId": "t", "placementId": "p", "priority": "brand_new"}
        """)
        #expect(meta.adId == "")            // number where string expected -> ""
        #expect(meta.creativeId == "")      // bool where string expected -> ""
        #expect(meta.templateId == "t")     // valid sibling still reads
        #expect(meta.priority == .unknown)  // unknown enum -> .unknown
    }

    // Scenario: engine metadata fields impId / skipOffsetSeconds / endCardMode are exposed
    @Test
    func testMetadataExposesImpIdAndVideoFields() throws {
        let meta = try decode(Metadata.self, """
        {
            "adId": "a", "creativeId": "c", "templateId": "t", "placementId": "p", "priority": "standard",
            "impId": "imp_abc123",
            "duration": 15, "aspectRatio": "16:9", "isSkippable": true,
            "skipOffsetSeconds": 5, "endCardMode": "auto"
        }
        """)
        #expect(meta.impId == "imp_abc123")
        #expect(meta.skipOffsetSeconds == 5)
        #expect(meta.endCardMode == "auto")

        // Absent on a normal ad -> nil (backward compatible, tolerant)
        let normal = try decode(Metadata.self, #"{"adId":"a","creativeId":"c","templateId":"t","placementId":"p","priority":"standard"}"#)
        #expect(normal.impId == nil)
        #expect(normal.skipOffsetSeconds == nil)
        #expect(normal.endCardMode == nil)
    }

    // Scenario: duration accepts an integer or a JSON number (Double)
    @Test
    func testMetadataDurationAcceptsIntOrDouble() throws {
        let asInt = try decode(Metadata.self, #"{"adId":"a","creativeId":"c","templateId":"t","placementId":"p","priority":"standard","duration": 30}"#)
        #expect(asInt.duration == 30)
        let asDouble = try decode(Metadata.self, #"{"adId":"a","creativeId":"c","templateId":"t","placementId":"p","priority":"standard","duration": 30.0}"#)
        #expect(asDouble.duration == 30)
    }

    // Scenario: Decision with a missing placement defaults to ""
    @Test
    func testDecisionMissingPlacement() throws {
        let decision = try decode(Decision.self, #"{"creatives": []}"#)
        #expect(decision.placement == "")
        #expect(decision.isNoAd)
    }

    // Scenario: a malformed creative inside a decision is dropped, others survive
    @Test
    func testMalformedCreativeDroppedFromDecision() throws {
        let decision = try decode(Decision.self, """
        {
            "placement": "home",
            "creatives": [
                {
                    "contents": [{"key": "title", "value": "Ok", "type": "string"}],
                    "advertiser": {"id": "adv1"},
                    "tracking": {},
                    "metadata": {"adId": "a", "creativeId": "c", "templateId": "t", "placementId": "p", "priority": "standard"}
                },
                42
            ]
        }
        """)
        #expect(decision.creatives?.count == 1)
        #expect(decision.hasCreative)
    }

    // Scenario: Advertiser/Template/VastData with retyped fields degrade, never throw
    @Test
    func testAdvertiserTemplateVastRetypedDegrade() throws {
        let adv = try decode(Advertiser.self, #"{"id": 5, "name": "Acme"}"#)
        #expect(adv.id == nil)          // number where string expected -> nil
        #expect(adv.name == "Acme")

        let tmpl = try decode(Template.self, #"{"style": "dark"}"#)
        #expect(tmpl.key == "")         // missing required key -> ""
        #expect(tmpl.style == "dark")

        let vast = try decode(VastData.self, #"{"tagUrl": 123}"#)
        #expect(vast.tagUrl == nil)     // retyped -> nil, no throw
    }

    // Scenario: OM resource keeps a usable script when only verificationParameters is missing
    @Test
    func testOMResourceKeptWhenOnlyParamsMissing() throws {
        let res = try decode(VerificationScriptResource.self, #"{"vendorKey": "v", "scriptUrl": "https://s/omid.js"}"#)
        #expect(res.verificationParameters == "")
        #expect(res.scriptUrl == "https://s/omid.js")
    }

    // Scenario: within a Creative, an OM resource missing scriptUrl is dropped; usable ones kept
    @Test
    func testOMResourceMissingScriptUrlDroppedInCreative() throws {
        let creative = try decode(Creative.self, """
        {
            "contents": [{"key": "title", "value": "Hi", "type": "string"}],
            "advertiser": {"id": "adv1"},
            "tracking": {},
            "metadata": {"adId": "a", "creativeId": "c", "templateId": "t", "placementId": "p", "priority": "standard"},
            "verificationScriptResources": [
                {"vendorKey": "v1", "scriptUrl": "https://s/1.js", "verificationParameters": "a=1"},
                {"vendorKey": "v2"}
            ]
        }
        """)
        // The entry missing scriptUrl is dropped; the usable one is kept.
        #expect(creative.verificationScriptResources?.count == 1)
        #expect(creative.verificationScriptResources?.first?.vendorKey == "v1")
    }

    // Scenario: errors array drops malformed entries but keeps well-formed ones
    @Test
    func testEnvelopeErrorsDropMalformed() throws {
        let body = try decode(APIResponseBody<DecisionResponse>.self, """
        {
            "success": false,
            "data": null,
            "errors": [
                {"code": 10009, "message": "bad field"},
                {"code": "not-an-int"},
                42
            ]
        }
        """)
        #expect(body.success == false)
        #expect(body.errors?.count == 1)
        #expect(body.errors?.first?.code == 10009)
    }
}
