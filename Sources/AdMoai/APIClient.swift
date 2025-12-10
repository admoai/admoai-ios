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
        urlRequest.timeoutInterval = 30

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

            #if DEBUG
                switch httpResponse.statusCode {
                case 200...499:
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
                case 500...599:
                    self.logger.error("Server error: \(httpResponse.statusCode)")
                    throw APIError.serverError(httpResponse.statusCode)
                default:
                    self.logger.error("Unexpected status code: \(httpResponse.statusCode)")
                    throw APIError.unexpectedStatusCode(httpResponse.statusCode)
                }
            #else
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
            #endif
        } catch let error as APIError {
            self.logger.error("\(error.description)")
            throw error
        } catch {
            self.logger.error("Network error: \(error.localizedDescription)")
            throw APIError.networkError(error)
        }
    }

    public func createDecisionRequest(_ request: DecisionRequest) throws -> HTTPRequest {
        let body = try JSONEncoder().encode(request)

        var headers: [String: String] = [
            "Content-Type": "application/json",
            "Accept": "application/json",
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
