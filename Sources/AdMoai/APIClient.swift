import Foundation
import OSLog

internal class AdMoaiClient {
    private let baseURL: String
    private let apiVersion: String?
    private let defaultLanguage: String?
    private let session: URLSession
    private let logger: Logger

    public init(
        baseURL: String,
        apiVersion: String? = nil,
        defaultLanguage: String? = nil,
        sessionConfiguration: URLSessionConfiguration = .default,
        logger: Logger
    ) {
        self.baseURL = baseURL
        self.apiVersion = apiVersion
        self.defaultLanguage = defaultLanguage
        self.logger = logger
        self.session = URLSession(configuration: sessionConfiguration)
    }

    private func send<T: Decodable>(_ request: HTTPRequest) async throws -> APIResponse<T> {
        guard let url = URL(string: "\(self.baseURL)\(request.path)") else {
            self.logger.error("Invalid URL: \(self.baseURL)\(request.path)")
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        // Deliberately does NOT pin a timeout here. A hardcoded 30s used to override whatever the
        // publisher configured on their URLSessionConfiguration, so `timeoutIntervalForRequest`
        // was silently ignored for every decision request. The session's value now applies.

        request.headers?.forEach { key, value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        if let body = request.body {
            urlRequest.httpBody = body
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type: \(type(of: response))")
                throw APIError.invalidResponse
            }

            // Deprecation-aware logging — runs for both build configurations (before the
            // DEBUG/release status switch). Scoped to decision responses: tracking is
            // fire-and-forget and does not inspect response headers (documented limitation).
            warnIfDeprecated(httpResponse)

            // One status contract for both build configurations.
            //
            // DEBUG used to treat 200...499 as success and attempt to decode, so a 400 or 422
            // surfaced as a decoded response while a release build raised a typed error for the
            // same response. A publisher integrating against a misconfigured placement saw the
            // request "work" in Xcode and fail in production — the worst possible split, because
            // the environment where you debug is the one that hides the error.
            //
            // The raw body is still logged in DEBUG below, so debug builds keep the diagnostic
            // detail without changing what the SDK returns.
            #if DEBUG
                if httpResponse.statusCode >= 400, let raw = String(data: data, encoding: .utf8) {
                    self.logger.debug(
                        "HTTP \(httpResponse.statusCode) body: \(raw, privacy: .public)")
                }
            #endif
                switch httpResponse.statusCode {
                case 200:
                    do {
                        let rawBody = String(data: data, encoding: .utf8)
                        return APIResponse(
                            response: httpResponse,
                            body: try JSONDecoder().decode(APIResponseBody<T>.self, from: data),
                            rawBody: rawBody
                        )
                    } catch {
                        self.logger.error("Decoding error: \(error.localizedDescription)")
                        throw APIError.decodingError(error)
                    }
                case 422:
                    do {
                        let response = try JSONDecoder().decode(
                            APIResponseBody<[AdMoaiError]>.self, from: data)
                        throw APIError.validationError(response.errors ?? [])
                    } catch let error as APIError {
                        self.logger.error("\(error.description)")
                        throw error
                    } catch {
                        self.logger.error("Validation error decoding failed: \(error)")
                        throw APIError.validationError([])
                    }
                case 400:
                    self.logger.error("Bad request error")
                    throw APIError.clientError(.badRequest)
                case 404:
                    self.logger.error("Not found error")
                    throw APIError.clientError(.notFound)
                case 405:
                    self.logger.error("Method not allowed error")
                    throw APIError.clientError(.methodNotAllowed)
                case 410:
                    self.logger.error("Gone error")
                    throw APIError.clientError(.gone)
                case 429:
                    self.logger.error("Too many requests error")
                    throw APIError.clientError(.tooManyRequests)
                case 500...599:
                    self.logger.error("Server error: \(httpResponse.statusCode)")
                    throw APIError.serverError(httpResponse.statusCode)
                default:
                    self.logger.error("Unexpected status code: \(httpResponse.statusCode)")
                    throw APIError.unexpectedStatusCode(httpResponse.statusCode)
                }
        } catch let error as APIError {
            self.logger.error("\(error.description)")
            throw error
        } catch {
            self.logger.error("Network error: \(error.localizedDescription)")
            throw APIError.networkError(error)
        }
    }

    /// Logs a one-line warning when the engine flags the negotiated API version as deprecated
    /// via `X-API-Deprecated: true`, surfacing the optional `Sunset` / `X-API-Sunset` date.
    private func warnIfDeprecated(_ response: HTTPURLResponse) {
        guard
            let message = AdMoaiClient.deprecationMessage(
                isDeprecated: response.value(forHTTPHeaderField: "X-API-Deprecated"),
                sunset: response.value(forHTTPHeaderField: "Sunset")
                    ?? response.value(forHTTPHeaderField: "X-API-Sunset")
            )
        else { return }
        self.logger.warning("\(message, privacy: .public)")
    }

    /// Pure, testable deprecation-message builder. Returns `nil` unless `isDeprecated` is
    /// exactly `"true"` (case-insensitive); otherwise a user-facing warning, including the
    /// sunset date when present.
    internal static func deprecationMessage(isDeprecated: String?, sunset: String?) -> String? {
        guard (isDeprecated ?? "").lowercased() == "true" else { return nil }
        if let sunset = sunset, !sunset.isEmpty {
            return "Admoai API version is deprecated (sunset: \(sunset)). Consider updating SDKConfig.apiVersion."
        }
        return "Admoai API version is deprecated. Consider updating SDKConfig.apiVersion."
    }

    public func createDecisionRequest(_ request: DecisionRequest) throws -> HTTPRequest {
        let body = try JSONEncoder().encode(request)

        var headers: [String: String] = [
            "Content-Type": "application/json",
            "Accept": "application/json",
            // Set per-request rather than relying on the session's httpAdditionalHeaders. A
            // publisher supplying their own URLSessionConfiguration silently dropped the SDK
            // User-Agent, which is what identifies SDK traffic in engine logs and analytics.
            "User-Agent": "AdMoaiSDK/\(SDK_VERSION)",
        ]
        
        // Add Accept-Language header if configured
        if let defaultLanguage = defaultLanguage {
            headers["Accept-Language"] = defaultLanguage
        }
        
        // Add API version header if configured
        if let apiVersion = apiVersion {
            headers["X-Decision-Version"] = apiVersion
        }

        return HTTPRequest(
            path: "/v1/decision",
            method: .post,
            headers: headers,
            body: body
        )
    }

    public func getDecisionRequest(_ request: DecisionRequest) throws -> HTTPRequest {
        try createDecisionRequest(request)
    }

    internal func requestDecision(_ request: DecisionRequest) async throws -> APIResponse<
        DecisionResponse
    > {
        let httpRequest = try createDecisionRequest(request)
        return try await send(httpRequest)
    }
}

public struct APIResponse<T: Decodable> {
    public let response: HTTPURLResponse
    public let body: APIResponseBody<T>
    public let rawBody: String?
}

public struct APIResponseBody<T: Decodable>: Decodable {
    public let success: Bool
    public let data: T?
    public let errors: [AdMoaiError]?
    public let warnings: [AdMoaiWarning]?
}

extension APIResponseBody {
    private enum TolerantKeys: String, CodingKey { case success, data, errors, warnings }

    /// Tolerant Reader envelope (PR B): never throws on a well-formed HTTP body. `success`
    /// reads as `== true` (default false), `data` degrades to `nil` if it fails to decode,
    /// and `errors`/`warnings` drop malformed entries.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TolerantKeys.self)
        self.success = (try? c.decode(Bool.self, forKey: .success)) ?? false
        // The decision list is the one array the generic `data` decode can't make
        // element-tolerant on its own — a single non-object entry would fail the whole
        // `[Decision]` decode. Special-case it so malformed/non-object decisions are dropped
        // and the good ones preserved, matching the Tolerant Reader policy for every other array.
        if T.self == DecisionResponse.self {
            if let decisions =
                (try? c.decode([SafelyDecodable<Decision>].self, forKey: .data))?.compactMap(\.value)
            {
                self.data = decisions as? T
            } else {
                self.data = nil
            }
        } else {
            self.data = try? c.decode(T.self, forKey: .data)
        }
        self.errors =
            (try? c.decode([SafelyDecodable<AdMoaiError>].self, forKey: .errors))?
            .compactMap(\.value)
        self.warnings =
            (try? c.decode([SafelyDecodable<AdMoaiWarning>].self, forKey: .warnings))?
            .compactMap(\.value)
    }
}

public struct AdMoaiError: Decodable, Equatable {
    public let code: Int
    public let message: String
}

public struct AdMoaiWarning: Decodable, Equatable {
    public let code: Int
    public let message: String
}

public enum APIError: Error, CustomStringConvertible, Equatable {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case invalidResponse
    case serverError(Int)
    case validationError([AdMoaiError])
    case clientError(HTTPStatus)
    case unexpectedStatusCode(Int)
    case encodingError(String)

    public var description: String {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code):
            return "Server error with status code: \(code)"
        case .validationError(let errors):
            if !errors.isEmpty {
                let messages = errors.map { "[\($0.code)] \($0.message)" }
                return "Validation errors:\n" + messages.joined(separator: "\n")
            }
            return "Validation error: Unknown"
        case .clientError(let status):
            return "Client error: \(status.rawValue) - \(status.description)"
        case .unexpectedStatusCode(let code):
            return "Unexpected status code: \(code)"
        case .encodingError(let message):
            return "Encoding error: \(message)"
        }
    }

    /// Four of the nine cases were missing, so `.clientError(.badRequest)` compared unequal to
    /// itself — the `default: return false` swallowed them. `APIError` is public and declares
    /// `Equatable`, so a publisher writing `error == .clientError(.notFound)` silently never
    /// matched. The remaining `default` now only covers genuinely different cases.
    public static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL):
            return true
        case (.invalidResponse, .invalidResponse):
            return true
        case (.networkError(let lhsError), .networkError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case (.decodingError(let lhsError), .decodingError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case (.serverError(let lhsCode), .serverError(let rhsCode)):
            return lhsCode == rhsCode
        case (.validationError(let lhsErrors), .validationError(let rhsErrors)):
            return lhsErrors == rhsErrors
        case (.clientError(let lhsStatus), .clientError(let rhsStatus)):
            return lhsStatus == rhsStatus
        case (.unexpectedStatusCode(let lhsCode), .unexpectedStatusCode(let rhsCode)):
            return lhsCode == rhsCode
        case (.encodingError(let lhsMessage), .encodingError(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

public struct HTTPRequest {
    public let path: String
    public let method: HTTPMethod
    public let headers: [String: String]?
    public let body: Data?

    public init(
        path: String,
        method: HTTPMethod,
        headers: [String: String]? = nil,
        body: Data? = nil
    ) {
        self.path = path
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

public enum HTTPStatus: Int {
    case ok = 200
    case badRequest = 400
    case notFound = 404
    case methodNotAllowed = 405
    case gone = 410
    case unprocessableEntity = 422
    case tooManyRequests = 429
    case internalServerError = 500

    var description: String {
        switch self {
        case .ok: return "OK"
        case .badRequest: return "Bad Request"
        case .notFound: return "Not Found"
        case .methodNotAllowed: return "Method Not Allowed"
        case .gone: return "Gone"
        case .unprocessableEntity: return "Unprocessable Entity"
        case .tooManyRequests: return "Too Many Requests"
        case .internalServerError: return "Internal Server Error"
        }
    }
}
