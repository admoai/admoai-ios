import Foundation
import Testing

@testable import AdMoai

// MARK: - OM Verification Serialization Tests

struct OMVerificationTests {

    // MARK: - VerificationScriptResource Deserialization

    @Test
    func testVerificationScriptResourceDeserialization() throws {
        let json = """
            {
                "vendorKey": "iabtechlab.com-omid",
                "scriptUrl": "https://verification.example.com/omid.js",
                "verificationParameters": "param1=value1&param2=value2"
            }
            """

        let data = json.data(using: .utf8)!
        let resource = try JSONDecoder().decode(VerificationScriptResource.self, from: data)

        #expect(resource.vendorKey == "iabtechlab.com-omid")
        #expect(resource.scriptUrl == "https://verification.example.com/omid.js")
        #expect(resource.verificationParameters == "param1=value1&param2=value2")
    }

    @Test
    func testVerificationScriptResourceWithEmptyParameters() throws {
        let json = """
            {
                "vendorKey": "doubleverify.com-omid",
                "scriptUrl": "https://cdn.doubleverify.com/dvtp_src.js",
                "verificationParameters": ""
            }
            """

        let data = json.data(using: .utf8)!
        let resource = try JSONDecoder().decode(VerificationScriptResource.self, from: data)

        #expect(resource.vendorKey == "doubleverify.com-omid")
        #expect(resource.scriptUrl == "https://cdn.doubleverify.com/dvtp_src.js")
        #expect(resource.verificationParameters == "")
    }

    @Test
    func testVerificationScriptResourceWithSpecialCharacters() throws {
        let json = """
            {
                "vendorKey": "ias.com-omid",
                "scriptUrl": "https://cdn.ias.com/verification.js?v=1.0",
                "verificationParameters": "anId=123&advId=456&campId=789&creativeId=abc-def_123"
            }
            """

        let data = json.data(using: .utf8)!
        let resource = try JSONDecoder().decode(VerificationScriptResource.self, from: data)

        #expect(resource.vendorKey == "ias.com-omid")
        #expect(resource.scriptUrl == "https://cdn.ias.com/verification.js?v=1.0")
        #expect(resource.verificationParameters == "anId=123&advId=456&campId=789&creativeId=abc-def_123")
    }

    @Test
    func testVerificationScriptResourceMissingRequiredField() throws {
        let json = """
            {
                "vendorKey": "iabtechlab.com-omid",
                "scriptUrl": "https://verification.example.com/omid.js"
            }
            """

        let data = json.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(VerificationScriptResource.self, from: data)
        }
    }

    // MARK: - Creative with VerificationScriptResources

    @Test
    func testCreativeWithSingleVerificationResource() throws {
        let json = """
            {
                "contents": [
                    {"key": "headline", "value": "Test Ad", "type": "text"}
                ],
                "advertiser": {"id": "adv123", "name": "Test Advertiser"},
                "tracking": {
                    "impressions": [{"key": "default", "url": "https://track.example.com/imp"}]
                },
                "verificationScriptResources": [
                    {
                        "vendorKey": "iabtechlab.com-omid",
                        "scriptUrl": "https://verification.example.com/omid.js",
                        "verificationParameters": "sessionId=abc123"
                    }
                ]
            }
            """

        let data = json.data(using: .utf8)!
        let creative = try JSONDecoder().decode(Creative.self, from: data)

        #expect(creative.hasOMVerification() == true)
        #expect(creative.verificationScriptResources?.count == 1)

        let resource = creative.getVerificationResources()?.first
        #expect(resource?.vendorKey == "iabtechlab.com-omid")
        #expect(resource?.scriptUrl == "https://verification.example.com/omid.js")
        #expect(resource?.verificationParameters == "sessionId=abc123")
    }

    @Test
    func testCreativeWithMultipleVerificationResources() throws {
        let json = """
            {
                "contents": [
                    {"key": "headline", "value": "Test Ad", "type": "text"}
                ],
                "advertiser": {"id": "adv123", "name": "Test Advertiser"},
                "tracking": {
                    "impressions": [{"key": "default", "url": "https://track.example.com/imp"}]
                },
                "verificationScriptResources": [
                    {
                        "vendorKey": "iabtechlab.com-omid",
                        "scriptUrl": "https://verification.iabtechlab.com/omid.js",
                        "verificationParameters": "sessionId=abc123"
                    },
                    {
                        "vendorKey": "doubleverify.com-omid",
                        "scriptUrl": "https://cdn.doubleverify.com/dvtp_src.js",
                        "verificationParameters": "ctx=1234567&cmp=DV123"
                    },
                    {
                        "vendorKey": "integralads.com-omid",
                        "scriptUrl": "https://cdn.adsafeprotected.com/iasPET.1.js",
                        "verificationParameters": "anId=929999"
                    }
                ]
            }
            """

        let data = json.data(using: .utf8)!
        let creative = try JSONDecoder().decode(Creative.self, from: data)

        #expect(creative.hasOMVerification() == true)
        #expect(creative.verificationScriptResources?.count == 3)

        let resources = creative.getVerificationResources()
        #expect(resources?.count == 3)

        // Verify each vendor is present
        let vendorKeys = resources?.map { $0.vendorKey } ?? []
        #expect(vendorKeys.contains("iabtechlab.com-omid"))
        #expect(vendorKeys.contains("doubleverify.com-omid"))
        #expect(vendorKeys.contains("integralads.com-omid"))
    }

    @Test
    func testCreativeWithEmptyVerificationResources() throws {
        let json = """
            {
                "contents": [
                    {"key": "headline", "value": "Test Ad", "type": "text"}
                ],
                "advertiser": {"id": "adv123", "name": "Test Advertiser"},
                "tracking": {
                    "impressions": [{"key": "default", "url": "https://track.example.com/imp"}]
                },
                "verificationScriptResources": []
            }
            """

        let data = json.data(using: .utf8)!
        let creative = try JSONDecoder().decode(Creative.self, from: data)

        #expect(creative.hasOMVerification() == false)
        #expect(creative.verificationScriptResources?.isEmpty == true)
        #expect(creative.getVerificationResources()?.isEmpty == true)
    }

    @Test
    func testCreativeWithNullVerificationResources() throws {
        let json = """
            {
                "contents": [
                    {"key": "headline", "value": "Test Ad", "type": "text"}
                ],
                "advertiser": {"id": "adv123", "name": "Test Advertiser"},
                "tracking": {
                    "impressions": [{"key": "default", "url": "https://track.example.com/imp"}]
                },
                "verificationScriptResources": null
            }
            """

        let data = json.data(using: .utf8)!
        let creative = try JSONDecoder().decode(Creative.self, from: data)

        #expect(creative.hasOMVerification() == false)
        #expect(creative.verificationScriptResources == nil)
        #expect(creative.getVerificationResources() == nil)
    }

    @Test
    func testCreativeWithoutVerificationResources() throws {
        let json = """
            {
                "contents": [
                    {"key": "headline", "value": "Test Ad", "type": "text"}
                ],
                "advertiser": {"id": "adv123", "name": "Test Advertiser"},
                "tracking": {
                    "impressions": [{"key": "default", "url": "https://track.example.com/imp"}]
                }
            }
            """

        let data = json.data(using: .utf8)!
        let creative = try JSONDecoder().decode(Creative.self, from: data)

        #expect(creative.hasOMVerification() == false)
        #expect(creative.verificationScriptResources == nil)
        #expect(creative.getVerificationResources() == nil)
    }

    // MARK: - Full API Response Deserialization

    @Test
    func testFullDecisionResponseWithOMVerification() throws {
        let json = """
            [
                {
                    "placement": "home",
                    "creatives": [
                        {
                            "contents": [
                                {"key": "headline", "value": "Premium Ad", "type": "text"},
                                {"key": "video_asset", "value": "https://cdn.example.com/video.mp4", "type": "video"}
                            ],
                            "advertiser": {
                                "id": "adv123",
                                "name": "Premium Brand",
                                "legalName": "Premium Brand Inc.",
                                "logoUrl": "https://cdn.example.com/logo.png"
                            },
                            "template": {"key": "video", "style": "fullscreen"},
                            "tracking": {
                                "impressions": [{"key": "default", "url": "https://track.example.com/imp"}],
                                "clicks": [{"key": "default", "url": "https://track.example.com/click"}],
                                "videoEvents": [
                                    {"key": "start", "url": "https://track.example.com/start"},
                                    {"key": "complete", "url": "https://track.example.com/complete"}
                                ]
                            },
                            "metadata": {
                                "adId": "ad123",
                                "creativeId": "cr456",
                                "advertiserId": "adv123",
                                "templateId": "tpl789",
                                "placementId": "pl001",
                                "priority": "high",
                                "format": "video",
                                "duration": 30,
                                "isSkippable": true
                            },
                            "delivery": "json",
                            "verificationScriptResources": [
                                {
                                    "vendorKey": "iabtechlab.com-omid",
                                    "scriptUrl": "https://verification.iabtechlab.com/omid.js",
                                    "verificationParameters": "sessionId=abc123&adId=ad123"
                                },
                                {
                                    "vendorKey": "moat.com-omid",
                                    "scriptUrl": "https://cdn.moat.com/moatad.js",
                                    "verificationParameters": "moatClientLevel1=12345&moatClientLevel2=67890"
                                }
                            ]
                        }
                    ]
                }
            ]
            """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(DecisionResponse.self, from: data)

        #expect(response.count == 1)

        let decision = response.first
        #expect(decision?.placement == "home")
        #expect(decision?.creatives?.count == 1)

        let creative = decision?.creatives?.first
        #expect(creative?.hasOMVerification() == true)
        #expect(creative?.verificationScriptResources?.count == 2)
        #expect(creative?.delivery == "json")

        // Verify first verification resource
        let firstResource = creative?.verificationScriptResources?.first
        #expect(firstResource?.vendorKey == "iabtechlab.com-omid")
        #expect(firstResource?.scriptUrl == "https://verification.iabtechlab.com/omid.js")
        #expect(firstResource?.verificationParameters.contains("sessionId=abc123") == true)
    }

    @Test
    func testDecisionResponseWithVastTagAndOMVerification() throws {
        let json = """
            [
                {
                    "placement": "preroll",
                    "creatives": [
                        {
                            "contents": [],
                            "advertiser": {"id": "adv123", "name": "Video Advertiser"},
                            "tracking": {
                                "impressions": [{"key": "default", "url": "https://track.example.com/imp"}]
                            },
                            "delivery": "vast_tag",
                            "vast": {
                                "tagUrl": "https://ads.example.com/vast?id=12345"
                            },
                            "verificationScriptResources": [
                                {
                                    "vendorKey": "doubleverify.com-omid",
                                    "scriptUrl": "https://cdn.doubleverify.com/dvtp_src.js",
                                    "verificationParameters": "ctx=1234567"
                                }
                            ]
                        }
                    ]
                }
            ]
            """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(DecisionResponse.self, from: data)

        let creative = response.first?.creatives?.first
        #expect(creative?.delivery == "vast_tag")
        #expect(creative?.vast?.tagUrl == "https://ads.example.com/vast?id=12345")
        #expect(creative?.hasOMVerification() == true)
        #expect(creative?.verificationScriptResources?.first?.vendorKey == "doubleverify.com-omid")
    }

    @Test
    func testDecisionResponseWithVastXmlAndOMVerification() throws {
        let json = """
            [
                {
                    "placement": "midroll",
                    "creatives": [
                        {
                            "contents": [],
                            "advertiser": {"id": "adv456", "name": "XML Advertiser"},
                            "tracking": {
                                "impressions": [{"key": "default", "url": "https://track.example.com/imp"}]
                            },
                            "delivery": "vast_xml",
                            "vast": {
                                "xmlBase64": "PFZBU1QgdmVyc2lvbj0iNC4yIj48L1ZBU1Q+"
                            },
                            "verificationScriptResources": [
                                {
                                    "vendorKey": "integralads.com-omid",
                                    "scriptUrl": "https://cdn.adsafeprotected.com/iasPET.1.js",
                                    "verificationParameters": "anId=929999&campId=12345"
                                }
                            ]
                        }
                    ]
                }
            ]
            """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(DecisionResponse.self, from: data)

        let creative = response.first?.creatives?.first
        #expect(creative?.delivery == "vast_xml")
        #expect(creative?.vast?.xmlBase64 == "PFZBU1QgdmVyc2lvbj0iNC4yIj48L1ZBU1Q+")
        #expect(creative?.hasOMVerification() == true)
    }

    @Test
    func testNativeAdWithoutOMVerification() throws {
        let json = """
            [
                {
                    "placement": "banner",
                    "creatives": [
                        {
                            "contents": [
                                {"key": "headline", "value": "Native Ad", "type": "text"},
                                {"key": "image", "value": "https://cdn.example.com/banner.jpg", "type": "image"}
                            ],
                            "advertiser": {"id": "adv789", "name": "Native Advertiser"},
                            "tracking": {
                                "impressions": [{"key": "default", "url": "https://track.example.com/imp"}],
                                "clicks": [{"key": "default", "url": "https://track.example.com/click"}]
                            }
                        }
                    ]
                }
            ]
            """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(DecisionResponse.self, from: data)

        let creative = response.first?.creatives?.first
        #expect(creative?.hasOMVerification() == false)
        #expect(creative?.verificationScriptResources == nil)
        #expect(creative?.delivery == nil)  // Native ads may not have delivery field
    }

    // MARK: - Edge Cases and Malformed Data

    @Test
    func testVerificationResourceWithUnicodeCharacters() throws {
        let json = """
            {
                "vendorKey": "测试vendor.com-omid",
                "scriptUrl": "https://verification.example.com/omid.js?name=テスト",
                "verificationParameters": "param=日本語&emoji=🎯"
            }
            """

        let data = json.data(using: .utf8)!
        let resource = try JSONDecoder().decode(VerificationScriptResource.self, from: data)

        #expect(resource.vendorKey == "测试vendor.com-omid")
        #expect(resource.scriptUrl.contains("テスト"))
        #expect(resource.verificationParameters.contains("日本語"))
    }

    @Test
    func testVerificationResourceWithVeryLongParameters() throws {
        let longParams = String(repeating: "x", count: 10000)
        let json = """
            {
                "vendorKey": "longparams.com-omid",
                "scriptUrl": "https://verification.example.com/omid.js",
                "verificationParameters": "\(longParams)"
            }
            """

        let data = json.data(using: .utf8)!
        let resource = try JSONDecoder().decode(VerificationScriptResource.self, from: data)

        #expect(resource.verificationParameters.count == 10000)
    }

    @Test
    func testVerificationResourceWithUrlEncodedParameters() throws {
        let json = """
            {
                "vendorKey": "encoded.com-omid",
                "scriptUrl": "https://verification.example.com/omid.js",
                "verificationParameters": "key%3Dvalue%26other%3D%E2%9C%93"
            }
            """

        let data = json.data(using: .utf8)!
        let resource = try JSONDecoder().decode(VerificationScriptResource.self, from: data)

        #expect(resource.verificationParameters == "key%3Dvalue%26other%3D%E2%9C%93")
    }

    @Test
    func testMalformedJsonMissingScriptUrl() throws {
        let json = """
            {
                "vendorKey": "broken.com-omid",
                "verificationParameters": "param=value"
            }
            """

        let data = json.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(VerificationScriptResource.self, from: data)
        }
    }

    @Test
    func testMalformedJsonMissingVendorKey() throws {
        let json = """
            {
                "scriptUrl": "https://verification.example.com/omid.js",
                "verificationParameters": "param=value"
            }
            """

        let data = json.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(VerificationScriptResource.self, from: data)
        }
    }

    @Test
    func testMalformedJsonWrongTypes() throws {
        let json = """
            {
                "vendorKey": 12345,
                "scriptUrl": "https://verification.example.com/omid.js",
                "verificationParameters": "param=value"
            }
            """

        let data = json.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(VerificationScriptResource.self, from: data)
        }
    }

    @Test
    func testMalformedJsonNullValues() throws {
        let json = """
            {
                "vendorKey": null,
                "scriptUrl": "https://verification.example.com/omid.js",
                "verificationParameters": "param=value"
            }
            """

        let data = json.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(VerificationScriptResource.self, from: data)
        }
    }

    // MARK: - Multiple Creatives with Mixed OM Status

    @Test
    func testMultipleCreativesWithMixedOMStatus() throws {
        let json = """
            [
                {
                    "placement": "mixed",
                    "creatives": [
                        {
                            "contents": [{"key": "headline", "value": "Ad 1", "type": "text"}],
                            "advertiser": {"id": "adv1", "name": "Advertiser 1"},
                            "tracking": {"impressions": [{"key": "default", "url": "https://track.example.com/imp1"}]},
                            "verificationScriptResources": [
                                {
                                    "vendorKey": "vendor1.com-omid",
                                    "scriptUrl": "https://vendor1.com/omid.js",
                                    "verificationParameters": "id=1"
                                }
                            ]
                        },
                        {
                            "contents": [{"key": "headline", "value": "Ad 2", "type": "text"}],
                            "advertiser": {"id": "adv2", "name": "Advertiser 2"},
                            "tracking": {"impressions": [{"key": "default", "url": "https://track.example.com/imp2"}]}
                        },
                        {
                            "contents": [{"key": "headline", "value": "Ad 3", "type": "text"}],
                            "advertiser": {"id": "adv3", "name": "Advertiser 3"},
                            "tracking": {"impressions": [{"key": "default", "url": "https://track.example.com/imp3"}]},
                            "verificationScriptResources": []
                        }
                    ]
                }
            ]
            """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(DecisionResponse.self, from: data)

        let creatives = response.first?.creatives
        #expect(creatives?.count == 3)

        // First creative has OM verification
        #expect(creatives?[0].hasOMVerification() == true)
        #expect(creatives?[0].verificationScriptResources?.count == 1)

        // Second creative has no OM verification (field missing)
        #expect(creatives?[1].hasOMVerification() == false)
        #expect(creatives?[1].verificationScriptResources == nil)

        // Third creative has empty OM verification array
        #expect(creatives?[2].hasOMVerification() == false)
        #expect(creatives?[2].verificationScriptResources?.isEmpty == true)
    }

    // MARK: - API Response Body Wrapper

    @Test
    func testAPIResponseBodyWithOMVerification() throws {
        let json = """
            {
                "success": true,
                "data": [
                    {
                        "placement": "home",
                        "creatives": [
                            {
                                "contents": [{"key": "headline", "value": "Test", "type": "text"}],
                                "advertiser": {"id": "adv1", "name": "Test Advertiser"},
                                "tracking": {"impressions": [{"key": "default", "url": "https://track.example.com/imp"}]},
                                "verificationScriptResources": [
                                    {
                                        "vendorKey": "test.com-omid",
                                        "scriptUrl": "https://test.com/omid.js",
                                        "verificationParameters": "test=true"
                                    }
                                ]
                            }
                        ]
                    }
                ],
                "errors": null,
                "warnings": null
            }
            """

        let data = json.data(using: .utf8)!
        let responseBody = try JSONDecoder().decode(
            APIResponseBody<DecisionResponse>.self, from: data)

        #expect(responseBody.success == true)
        #expect(responseBody.data?.count == 1)

        let creative = responseBody.data?.first?.creatives?.first
        #expect(creative?.hasOMVerification() == true)
    }

    @Test
    func testAPIResponseBodyWithErrorsNoData() throws {
        let json = """
            {
                "success": false,
                "data": null,
                "errors": [
                    {"code": 422, "message": "Invalid placement"}
                ],
                "warnings": null
            }
            """

        let data = json.data(using: .utf8)!
        let responseBody = try JSONDecoder().decode(
            APIResponseBody<DecisionResponse>.self, from: data)

        #expect(responseBody.success == false)
        #expect(responseBody.data == nil)
        #expect(responseBody.errors?.count == 1)
        #expect(responseBody.errors?.first?.code == 422)
    }
}
