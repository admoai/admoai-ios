import Foundation

@testable import AdMoai

/// Stateless HTTP stub: answers every request with `200 []` and records nothing.
///
/// For tests that must not reach the network but do not care what was sent — the
/// documented-API compile check, for instance, which only needs the documented calls to *exist*
/// and to be safe to invoke.
///
/// Deliberately keeps **no** shared state, so unlike ``MockURLProtocol`` it can be used from a
/// suite that runs in parallel with anything else. Reach for `MockURLProtocol` (and the
/// serialized ``MockNetworkTests`` suite) only when a test needs to inspect what was sent.
final class BlackHoleURLProtocol: URLProtocol {
    static func config(
        baseUrl: String = "https://api.admoai.com",
        apiVersion: String? = nil,
        defaultLanguage: String? = nil
    ) -> SDKConfig {
        let sc = URLSessionConfiguration.ephemeral
        sc.protocolClasses = [BlackHoleURLProtocol.self]
        return SDKConfig(
            baseUrl: baseUrl,
            apiVersion: apiVersion,
            defaultLanguage: defaultLanguage,
            sessionConfiguration: sc
        )
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url ?? URL(string: "https://mock.invalid")!
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("[]".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
