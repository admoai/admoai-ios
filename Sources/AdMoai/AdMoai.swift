import Foundation
import OSLog

// MARK: - AdMoai SDK
public struct AdMoai {
    private let client: AdMoaiClient
    public private(set) var config: SDKConfig
    public private(set) var appConfig: AppConfig
    public private(set) var deviceConfig: DeviceConfig
    public private(set) var userConfig: UserConfig
    private let session: URLSession

    /// Journey Takeover Ads: sticky, publisher-owned session identifier inherited by every
    /// request builder created via ``createRequestBuilder()``. Rotate it explicitly with
    /// ``setSessionId(_:)``; the SDK never generates or mutates it on its own.
    private var _sessionId: String?

    public init(
        config: SDKConfig,
        userConfig: UserConfig? = nil,
        sessionId: String? = nil
    ) {
        self.config = config
        self.appConfig = .systemDefault()
        self.deviceConfig = .systemDefault()
        self.userConfig = userConfig ?? .clear()
        self._sessionId = AdMoai.normalizedSessionId(sessionId, logger: config.logger)

        self.client = AdMoaiClient(
            baseURL: config.baseUrl,
            apiVersion: config.apiVersion,
            defaultLanguage: config.defaultLanguage,
            sessionConfiguration: config.sessionConfiguration,
            logger: config.logger
        )

        self.session = URLSession(configuration: config.sessionConfiguration)
    }

    // MARK: - App Configuration
    public mutating func setAppConfig(
        name: String? = nil,
        version: String? = nil,
        buildNumber: String? = nil,
        identifier: String? = nil,
        language: String? = nil
    ) {
        let current = appConfig
        self.appConfig = AppConfig(
            name: name ?? current.name,
            version: version ?? current.version,
            buildNumber: buildNumber ?? current.buildNumber,
            identifier: identifier ?? current.identifier,
            language: language ?? current.language
        )
    }

    public mutating func clearAppConfig() {
        self.appConfig = .clear()
    }

    public mutating func resetAppConfig() {
        self.appConfig = .systemDefault()
    }

    // MARK: - Device Configuration
    public mutating func setDeviceConfig(
        id: String? = nil,
        model: String? = nil,
        manufacturer: String? = nil,
        os: String? = nil,
        osVersion: String? = nil,
        timezone: String? = nil,
        language: String? = nil
    ) {
        let current = deviceConfig
        self.deviceConfig = DeviceConfig(
            id: id ?? current.id,
            model: model ?? current.model,
            manufacturer: manufacturer ?? current.manufacturer,
            os: os ?? current.os,
            osVersion: osVersion ?? current.osVersion,
            timezone: timezone ?? current.timezone,
            language: language ?? current.language
        )
    }

    public mutating func clearDeviceConfig() {
        self.deviceConfig = .clear()
    }

    public mutating func resetDeviceConfig() {
        self.deviceConfig = .systemDefault()
    }

    // MARK: - User Configuration
    public mutating func setUserConfig(
        id: String? = nil,
        ip: String? = nil,
        timezone: String? = nil,
        consent: User.Consent? = nil
    ) {
        let current = userConfig
        self.userConfig = UserConfig(
            id: id ?? current.id,
            ip: ip ?? current.ip,
            timezone: timezone ?? current.timezone,
            consent: consent ?? current.consent
        )
    }

    public mutating func clearUserConfig() {
        self.userConfig = .clear()
    }

    // MARK: - Journey Session
    /// The current sticky Journey `sessionId`, normalized to wire form (trimmed; `nil` when blank).
    public var sessionId: String? { _sessionId }

    /// Rotates the sticky Journey `sessionId` inherited by future request builders.
    /// The value is normalized to wire form (trimmed; blank → `nil`) so the stored value
    /// matches what is sent. Rotation is entirely publisher-driven.
    public mutating func setSessionId(_ sessionId: String?) {
        self._sessionId = AdMoai.normalizedSessionId(sessionId, logger: config.logger)
    }

    public mutating func clearSessionId() {
        self._sessionId = nil
    }

    /// Normalizes a raw `sessionId` to wire form (trim; blank → `nil`) and emits a PII-safe
    /// warning when it would be rejected by the engine. Never logs the value itself.
    private static func normalizedSessionId(_ raw: String?, logger: Logger) -> String? {
        guard let raw = raw else { return nil }
        if let reason = DecisionRequest.journeySessionIdRejectionReason(raw) {
            logger.warning("Journey sessionId will be ignored by the engine: \(reason, privacy: .public)")
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - SDK Operations
    public func createRequestBuilder() -> DecisionRequestBuilder {
        return DecisionRequestBuilder(
            appConfig: appConfig,
            deviceConfig: deviceConfig,
            userConfig: userConfig,
            sessionId: _sessionId,
            logger: config.logger
        )
    }

    public func requestAds(_ request: DecisionRequest) async throws -> APIResponse<DecisionResponse>
    {
        try await client.requestDecision(request)
    }

    public func getHttpRequest(_ request: DecisionRequest) throws -> HTTPRequest {
        try client.getDecisionRequest(request)
    }

    // MARK: - Tracking
    public func fireTracking(url: String) {
        guard let parsedURL = URL(string: url) else {
            config.logger.error("Invalid tracking URL: \(url)")
            return
        }
        var request = URLRequest(
            url: parsedURL,
            timeoutInterval: config.sessionConfiguration.timeoutIntervalForRequest
        )
        if let defaultLanguage = config.defaultLanguage {
            request.setValue(defaultLanguage, forHTTPHeaderField: "Accept-Language")
        }
        if let apiVersion = config.apiVersion {
            request.setValue(apiVersion, forHTTPHeaderField: "X-Decision-Version")
        }
        session.dataTask(with: request).resume()
    }

    public func fireImpression(tracking: Tracking, key: String = "default") {
        if let url = tracking.getImpressionUrl(key: key) {
            fireTracking(url: url)
        }
    }

    public func fireClick(tracking: Tracking, key: String = "default") {
        if let url = tracking.getClickUrl(key: key) {
            fireTracking(url: url)
        }
    }

    public func fireCustom(tracking: Tracking, key: String) {
        if let url = tracking.getCustomUrl(key: key) {
            fireTracking(url: url)
        }
    }

    public func fireVideoEvent(tracking: Tracking, key: String) {
        if let url = tracking.getVideoEventUrl(key: key) {
            fireTracking(url: url)
        }
    }
}
