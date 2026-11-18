@testable import AdMoai
import Foundation
import Testing

/// Wave 3 (F20): DEBUG and release builds must share one HTTP status contract.

// MARK: - F20: DEBUG and release share one status contract

extension MockNetworkTests {
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
                stub: .init(statusCode: 422, body: Data(envelope.utf8))
            )

            let sdk = AdMoai(config: MockURLProtocol.config(apiVersion: "2025-11-01"))
            let request = sdk.createRequestBuilder().addPlacement(key: "home").build()

            do {
                _ = try await sdk.requestAds(request)
                Issue.record("a 422 must raise, not decode, in a DEBUG build")
            } catch let error as APIError {
                guard case let .validationError(errors) = error else {
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
                stub: .init(statusCode: 400, body: Data(#"{"success":false}"#.utf8))
            )

            let sdk = AdMoai(config: MockURLProtocol.config(apiVersion: "2025-11-01"))
            let request = sdk.createRequestBuilder().addPlacement(key: "home").build()

            await #expect(throws: APIError.clientError(.badRequest)) {
                _ = try await sdk.requestAds(request)
            }
        }

        // Scenario: a 400 the engine explains carries the engine's code to the app (admoai-ios#93).
        @Test
        func testBadRequestWithEngineErrorsCarriesTheCode() async throws {
            // The exact body the engine sends when a workspace without audience signals gets a
            // device field it does not accept (B5-ios QA run, step 4).
            let envelope = #"""
            {"success":false,"data":null,"errors":[{"code":10009,"message":"The body contains an unknown field `\"category\"`"}],"warnings":null}
            """#
            MockURLProtocol.reset(stub: .init(statusCode: 400, body: Data(envelope.utf8)))

            let sdk = AdMoai(config: MockURLProtocol.config(apiVersion: "2025-11-01"))
            let request = sdk.createRequestBuilder().addPlacement(key: "home").build()

            do {
                _ = try await sdk.requestAds(request)
                Issue.record("a 400 must raise")
            } catch let error as APIError {
                guard case let .requestRejected(status, errors) = error else {
                    Issue.record("expected .requestRejected, got \(error)")
                    return
                }
                #expect(status == 400)
                #expect(errors.map(\.code) == [10009])
                #expect(errors.first?.message == "The body contains an unknown field `\"category\"`")
                #expect(error.engineErrors.map(\.code) == [10009])
                #expect(error.description.contains("[10009]"))
            }
        }

        // Scenario: a 4xx whose body is not the engine's envelope keeps its old error.
        @Test(arguments: [
            (400, "", APIError.clientError(.badRequest)),
            (400, "<html>Bad Request</html>", APIError.clientError(.badRequest)),
            (400, #"{"success":false,"data":null,"errors":[],"warnings":null}"#, APIError.clientError(.badRequest)),
            (404, "", APIError.clientError(.notFound)),
            (418, "", APIError.unexpectedStatusCode(418)),
        ])
        func testClientErrorWithoutEngineErrorsIsUnchanged(status: Int, body: String, expected: APIError) async throws {
            MockURLProtocol.reset(stub: .init(statusCode: status, body: Data(body.utf8)))

            let sdk = AdMoai(config: MockURLProtocol.config(apiVersion: "2025-11-01"))
            let request = sdk.createRequestBuilder().addPlacement(key: "home").build()

            await #expect(throws: expected) {
                _ = try await sdk.requestAds(request)
            }
            #expect(expected.engineErrors.isEmpty)
        }

        // Scenario: any other 4xx the engine explains carries its code too, with its own status.
        @Test
        func testOtherClientErrorWithEngineErrorsCarriesTheCode() async throws {
            let envelope = #"{"success":false,"data":null,"errors":[{"code":42,"message":"slow down"}]}"#
            MockURLProtocol.reset(stub: .init(statusCode: 429, body: Data(envelope.utf8)))

            let sdk = AdMoai(config: MockURLProtocol.config(apiVersion: "2025-11-01"))
            let request = sdk.createRequestBuilder().addPlacement(key: "home").build()

            await #expect(throws: APIError.requestRejected(
                status: 429, errors: [AdMoaiError(code: 42, message: "slow down")]
            )) {
                _ = try await sdk.requestAds(request)
            }
        }

        // Scenario: a 422 is unchanged, and its codes read the same way.
        @Test
        func testValidationErrorExposesEngineErrors() {
            let errors = [AdMoaiError(code: 10028, message: "audience signals are not enabled")]
            #expect(APIError.validationError(errors).engineErrors == errors)
            #expect(APIError.serverError(500).engineErrors.isEmpty)
            #expect(APIError.requestRejected(status: 400, errors: errors)
                == APIError.requestRejected(status: 400, errors: errors))
            #expect(APIError.requestRejected(status: 400, errors: errors)
                != APIError.requestRejected(status: 404, errors: errors))
            #expect(APIError.requestRejected(status: 422, errors: errors) != APIError.validationError(errors))
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
