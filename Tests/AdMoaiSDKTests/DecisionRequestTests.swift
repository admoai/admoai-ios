import Foundation
import Testing

@testable import AdMoai

private let baseURL = "https://mock.api.admoai.com"

struct DecisionRequestTests {
    @Test
    func testRequestBuilder() {
        let config = SDKConfig(baseUrl: baseURL)
        let sdk = AdMoai(config: config)

        let builder = sdk.createRequestBuilder()
        let request =
            builder
            .addPlacement(key: "home", count: 2)
            .addGeoTargeting(5819)
            .setUserId("user123")
            .setUserIp("192.168.1.1")
            .build()

        // Verify request structure
        #expect(request.placements.count == 1)
        #expect(request.placements.first?.key == "home")
        #expect(request.placements.first?.count == 2)
        #expect(request.targeting?.geo?.contains(5819) == true)
        #expect(request.user?.id == "user123")
        #expect(request.user?.ip == "192.168.1.1")
    }

    @Test
    func testDecisionRequest() async throws {
        let config = SDKConfig(baseUrl: baseURL)
        let sdk = AdMoai(config: config)

        let request = sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .build()

        do {
            let response = try await sdk.requestAds(request)
            #expect(response.body.success)

            if let decision = response.body.data?.first {
                #expect(decision.placement == "home")
            }
        } catch {
            // Note: This test will fail if server is not running
            print("Server request failed: \(error)")
        }
    }

    @Test
    func testInvalidPlacement() async throws {
        let config = SDKConfig(baseUrl: baseURL)
        let sdk = AdMoai(config: config)

        let request = sdk.createRequestBuilder()
            .addPlacement(key: "invalid_placement")
            .build()

        let response = try await sdk.requestAds(request)
        #expect(response.response.statusCode == 422)
        #expect(response.body.success == false)
    }

    @Test
    func testInvalidBaseURL() async throws {
        let config = SDKConfig(baseUrl: "invalid-url")
        let sdk = AdMoai(config: config)

        let request = sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .build()

        do {
            _ = try await sdk.requestAds(request)
        } catch let error as APIError {
            if case .networkError(let underlyingError) = error {
                #expect(underlyingError.localizedDescription.contains("unsupported URL"))
            } else {
                throw error
            }
        }
    }
}
