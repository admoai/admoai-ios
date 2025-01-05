import Foundation
import Testing

@testable import AdMoai

private let baseURL = "https://mock.api.admoai.com"
private let config = SDKConfig(baseUrl: baseURL)
private let sdk = AdMoai(config: config)

struct DecisionRequestTests {
    @Test
    func testBasicRequestBuilder() {
        let builder = sdk.createRequestBuilder()
        let request =
            builder
            .addPlacement(key: "home", count: 2)
            .addGeoTargeting(5819)
            .addLocationTargeting(latitude: 40.7128, longitude: -74.0060)  // NYC
            .addLocationTargeting(51.5074, -0.1278)  // London
            .setUserId("user123")
            .setUserIp("192.168.1.1")
            .build()

        // Verify basic request structure
        #expect(request.placements.count == 1)
        #expect(request.placements.first?.key == "home")
        #expect(request.placements.first?.count == 2)
        #expect(request.targeting?.geo?.contains(5819) == true)
        #expect(request.targeting?.location?.count == 2)
        #expect(request.targeting?.location?.first?.latitude == 40.7128)
        #expect(request.targeting?.location?.first?.longitude == -74.0060)
        #expect(request.targeting?.location?.last?.latitude == 51.5074)
        #expect(request.targeting?.location?.last?.longitude == -0.1278)
        #expect(request.user?.id == "user123")
        #expect(request.user?.ip == "192.168.1.1")
    }

    @Test
    func testLocationTargeting() {
        let builder = sdk.createRequestBuilder()

        // Test addLocationTargeting
        var request =
            builder
            .addLocationTargeting(latitude: 40.7128, longitude: -74.0060)  // NYC
            .addLocationTargeting(latitude: 51.5074, longitude: -0.1278)  // London
            .addLocationTargeting(48.8566, 2.3522)  // Paris
            .build()

        // Verify total count
        #expect(request.targeting?.location?.count == 3)

        // Verify each location exists
        #expect(
            request.targeting?.location?.contains(where: { coord in
                coord.latitude == 40.7128 && coord.longitude == -74.0060  // NYC
            }) == true)
        #expect(
            request.targeting?.location?.contains(where: { coord in
                coord.latitude == 51.5074 && coord.longitude == -0.1278  // London
            }) == true)
        #expect(
            request.targeting?.location?.contains(where: { coord in
                coord.latitude == 48.8566 && coord.longitude == 2.3522  // Paris
            }) == true)

        // Test setLocationTargeting with fresh builder
        request = sdk.createRequestBuilder()
            .setLocationTargeting([
                (latitude: 40.7128, longitude: -74.0060),  // NYC
                (latitude: 51.5074, longitude: -0.1278),  // London
                (48.8566, 2.3522),  // Paris
            ])
            .build()

        // Verify same behavior with setLocationTargeting
        #expect(request.targeting?.location?.count == 3)
        #expect(
            request.targeting?.location?.contains(where: { coord in
                coord.latitude == 40.7128 && coord.longitude == -74.0060  // NYC
            }) == true)
        #expect(
            request.targeting?.location?.contains(where: { coord in
                coord.latitude == 51.5074 && coord.longitude == -0.1278  // London
            }) == true)
        #expect(
            request.targeting?.location?.contains(where: { coord in
                coord.latitude == 48.8566 && coord.longitude == 2.3522  // Paris
            }) == true)
    }

    @Test
    func testLocationTargetingUniqueness() {
        let builder = sdk.createRequestBuilder()

        // Test addLocationTargeting with duplicates
        var request =
            builder
            .addLocationTargeting(latitude: 40.7128, longitude: -74.0060)  // NYC
            .addLocationTargeting(latitude: 51.5074, longitude: -0.1278)  // London
            .addLocationTargeting(latitude: 40.7128, longitude: -74.0060)  // NYC (duplicate)
            .addLocationTargeting(latitude: 48.8566, longitude: 2.3522)  // Paris
            .addLocationTargeting(latitude: 51.5074, longitude: -0.1278)  // London (duplicate)
            .build()

        // Should only have 3 unique locations
        #expect(request.targeting?.location?.count == 3)

        // Verify each city exists exactly once
        let nycCount = request.targeting?.location?.filter { coord in
            coord.latitude == 40.7128 && coord.longitude == -74.0060
        }.count
        #expect(nycCount == 1, "Expected one occurrence of NYC")

        let londonCount = request.targeting?.location?.filter { coord in
            coord.latitude == 51.5074 && coord.longitude == -0.1278
        }.count
        #expect(londonCount == 1, "Expected one occurrence of London")

        let parisCount = request.targeting?.location?.filter { coord in
            coord.latitude == 48.8566 && coord.longitude == 2.3522
        }.count
        #expect(parisCount == 1, "Expected one occurrence of Paris")

        // Test setLocationTargeting with duplicates
        request = sdk.createRequestBuilder()
            .setLocationTargeting([
                (latitude: 40.7128, longitude: -74.0060),  // NYC
                (latitude: 51.5074, longitude: -0.1278),  // London
                (latitude: 40.7128, longitude: -74.0060),  // NYC (duplicate)
                (latitude: 48.8566, longitude: 2.3522),  // Paris
                (latitude: 51.5074, longitude: -0.1278),  // London (duplicate)
            ])
            .build()

        // Same uniqueness checks for setLocationTargeting
        #expect(request.targeting?.location?.count == 3)

        #expect(
            request.targeting?.location?.filter { coord in
                coord.latitude == 40.7128 && coord.longitude == -74.0060
            }.count == 1, "Expected one occurrence of NYC")

        #expect(
            request.targeting?.location?.filter { coord in
                coord.latitude == 51.5074 && coord.longitude == -0.1278
            }.count == 1, "Expected one occurrence of London")

        #expect(
            request.targeting?.location?.filter { coord in
                coord.latitude == 48.8566 && coord.longitude == 2.3522
            }.count == 1, "Expected one occurrence of Paris")
    }

    @Test
    func testCustomTargeting() {
        let builder = sdk.createRequestBuilder()
        let request =
            builder
            .addCustomTargeting(key: "age", value: 25)  // Int
            .addCustomTargeting(key: "score", value: 98.6)  // Double
            .addCustomTargeting(key: "name", value: "John")  // String
            .addCustomTargeting(key: "premium", value: true)  // Bool
            .build()

        #expect(request.targeting?.custom?.count == 4)
        #expect(
            request.targeting?.custom?.contains(where: { kv in
                kv.key == "age" && kv.value as? Int == 25
            }) == true)
        #expect(
            request.targeting?.custom?.contains(where: { kv in
                kv.key == "score" && kv.value as? Double == 98.6
            }) == true)
        #expect(
            request.targeting?.custom?.contains(where: { kv in
                kv.key == "name" && kv.value as? String == "John"
            }) == true)
        #expect(
            request.targeting?.custom?.contains(where: { kv in
                kv.key == "premium" && kv.value as? Bool == true
            }) == true)
    }

    @Test
    func testCustomTargetingUniqueness() {
        let builder = sdk.createRequestBuilder()
        let request =
            builder
            .addCustomTargeting(key: "category", value: "sports")
            .addCustomTargeting(key: "hello", value: "bye")
            .addCustomTargeting(key: "category", value: "news")  // Should override "sports"
            .addCustomTargeting(key: "score", value: 100)
            .addCustomTargeting(key: "score", value: 95.5)  // Should override 100
            .addCustomTargeting(key: "premium", value: false)
            .addCustomTargeting(key: "premium", value: true)  // Should override false
            .build()

        #expect(request.targeting?.custom?.count == 4)
        #expect(
            request.targeting?.custom?.contains(where: { kv in
                kv.key == "category" && kv.value as? String == "news"
            }) == true)
        #expect(
            request.targeting?.custom?.contains(where: { kv in
                kv.key == "score" && kv.value as? Double == 95.5
            }) == true)
        #expect(
            request.targeting?.custom?.contains(where: { kv in
                kv.key == "premium" && kv.value as? Bool == true
            }) == true)
        #expect(
            request.targeting?.custom?.contains(where: { kv in
                kv.key == "hello" && kv.value as? String == "bye"
            }) == true)

        // Verify overwritten values don't exist
        #expect(
            request.targeting?.custom?.contains(where: { kv in
                kv.key == "category" && kv.value as? String == "sports"
            }) == false)
        #expect(
            request.targeting?.custom?.contains(where: { kv in
                kv.key == "score" && kv.value as? Int == 100
            }) == false)
        #expect(
            request.targeting?.custom?.contains(where: { kv in
                kv.key == "premium" && kv.value as? Bool == false
            }) == false)
    }

    @Test
    func testDecisionRequest() async throws {
        let config = SDKConfig(baseUrl: baseURL)
        let sdk = AdMoai(config: config)

        let request = sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .addLocationTargeting(latitude: 40.7128, longitude: -74.0060)
            .addLocationTargeting(latitude: 51.5074, longitude: -0.1278)
            .addCustomTargeting(key: "category", value: "news")
            .addCustomTargeting(key: "category", value: "sports")
            .setUserId("user123")
            .setUserIp("192.168.1.1")
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
