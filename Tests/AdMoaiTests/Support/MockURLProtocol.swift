import Foundation

@testable import AdMoai

/// In-process HTTP stub for deterministic SDK tests.
///
/// Injected via `SDKConfig.sessionConfiguration.protocolClasses`, which feeds BOTH the
/// decision session (`AdMoaiClient`) and the fire-and-forget tracking session (`AdMoai`),
/// so a single stub covers every request the SDK makes — including the opaque tracking
/// GETs whose headers are otherwise unobservable.
final class MockURLProtocol: URLProtocol {
    struct Stub {
        var statusCode: Int = 200
        var body: Data = Data("[]".utf8)
        var headers: [String: String] = ["Content-Type": "application/json"]
    }

    private static let lock = NSLock()
    private static var _stub = Stub()
    private static var _requests: [URLRequest] = []

    /// Resets captured requests and installs a stub. Call in each test before exercising the SDK.
    static func reset(stub: Stub = Stub()) {
        lock.lock(); defer { lock.unlock() }
        _stub = stub
        _requests = []
    }

    static var capturedRequests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    static var lastRequest: URLRequest? { capturedRequests.last }

    /// Builds an `SDKConfig` whose sessions route through this protocol.
    static func config(
        baseUrl: String = "https://api.mock.admoai.com",
        apiVersion: String? = nil,
        defaultLanguage: String? = nil
    ) -> SDKConfig {
        let sc = URLSessionConfiguration.ephemeral
        sc.protocolClasses = [MockURLProtocol.self]
        return SDKConfig(
            baseUrl: baseUrl,
            apiVersion: apiVersion,
            defaultLanguage: defaultLanguage,
            sessionConfiguration: sc
        )
    }

    /// Waits (polling) until at least `count` requests have been captured, or a timeout.
    /// Needed because tracking is fire-and-forget (no completion to await).
    @discardableResult
    static func waitForRequests(_ count: Int, timeout: TimeInterval = 2.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if capturedRequests.count >= count { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)  // 10 ms
        }
        return capturedRequests.count >= count
    }

    private static func record(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        _requests.append(request)
    }

    private static var currentStub: Stub {
        lock.lock(); defer { lock.unlock() }
        return _stub
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.record(request)
        let stub = MockURLProtocol.currentStub
        let url = request.url ?? URL(string: "https://mock.invalid")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
