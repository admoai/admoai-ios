import Foundation
import Testing

@testable import AdMoai

/// Wave 3 (F20): DEBUG and release builds must share one HTTP status contract.

// MARK: - F20: DEBUG and release share one status contract

extension MockNetworkTests {
    @Suite
    struct DebugReleaseStatusParityTests {

        // Scenario: the engine rejects a request with a validation error, in a DEBUG build.
        @Test
        func testValidationErrorRaisesInDebugToo() async throws {
            // DEBUG used to treat 200...499 as success and attempt to decode, so a 422 came back
            // as a decoded response while release raised APIError.validationError for the same
            // bytes. A publisher saw the request "work" in Xcode and fail in production — the
            // worst possible split, since the environment where you debug is the one that hides
            // the error. This test necessarily runs in DEBUG, which is exactly the point.
            let envelope = """
                {"success":false,"data":null,
                 "errors":[{"code":10004,"message":"placement key home was not found"}],
                 "warnings":null}
                """
            MockURLProtocol.reset(
                stub: .init(statusCode: 422, body: Data(envelope.utf8)))

            let sdk = AdMoai(config: MockURLProtocol.config(apiVersion: "2025-11-01"))
            let request = sdk.createRequestBuilder().addPlacement(key: "home").build()

            do {
                _ = try await sdk.requestAds(request)
                Issue.record("a 422 must raise, not decode, in a DEBUG build")
            } catch let error as APIError {
                guard case .validationError(let errors) = error else {
                    Issue.record("expected .validationError, got \(error)")
                    return
                }
                #expect(errors.first?.code == 10004)
            }
        }

        // Scenario: a 400 in a DEBUG build.
        @Test
        func testBadRequestRaisesInDebugToo() async throws {
            MockURLProtocol.reset(
                stub: .init(statusCode: 400, body: Data(#"{"success":false}"#.utf8)))

            let sdk = AdMoai(config: MockURLProtocol.config(apiVersion: "2025-11-01"))
            let request = sdk.createRequestBuilder().addPlacement(key: "home").build()

            await #expect(throws: APIError.clientError(.badRequest)) {
                _ = try await sdk.requestAds(request)
            }
        }

        // Scenario: a publisher compares a thrown error against an expected case.
        @Test
        func testAPIErrorEqualityCoversEveryCase() {
            // Found by the test above: `.clientError`, `.validationError`, `.unexpectedStatusCode`
            // and `.encodingError` all fell through to `default: return false`, so each compared
            // unequal to ITSELF. APIError is public and declares Equatable, so
            // `error == .clientError(.notFound)` silently never matched.
            #expect(APIError.clientError(.badRequest) == APIError.clientError(.badRequest))
            #expect(APIError.clientError(.badRequest) != APIError.clientError(.notFound))
            #expect(APIError.unexpectedStatusCode(418) == APIError.unexpectedStatusCode(418))
            #expect(APIError.encodingError("a") == APIError.encodingError("a"))

            let one = [AdMoaiError(code: 1, message: "x")]
            #expect(APIError.validationError(one) == APIError.validationError(one))
            #expect(APIError.validationError(one) != APIError.validationError([]))
            // Different cases must still compare unequal.
            #expect(APIError.invalidURL != APIError.invalidResponse)
        }

        // Scenario: a normal 200 is unaffected by the unified status handling.
        @Test
        func testSuccessStillDecodes() async throws {
            let body = #"{"success":true,"data":[{"placement":"home","creatives":[]}]}"#
            MockURLProtocol.reset(stub: .init(statusCode: 200, body: Data(body.utf8)))

            let sdk = AdMoai(config: MockURLProtocol.config(apiVersion: "2025-11-01"))
            let request = sdk.createRequestBuilder().addPlacement(key: "home").build()

            let response = try await sdk.requestAds(request)
            #expect(response.body.success)
            #expect(response.body.data?.first?.placement == "home")
        }
    }
}
