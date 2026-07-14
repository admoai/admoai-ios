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
        if let reason = DecisionRequest.journeySessionIdRejectionReason(raw) {
            logger.warning("Journey sessionId will be ignored by the engine: \(reason, privacy: .public)")
        }
        return DecisionRequest.normalizedSessionId(raw)
    }

    // MARK: - SDK Operations
    public func createRequestBuilder() -> DecisionRequestBuilder {
        return DecisionRequestBuilder(
            appConfig: appConfig,
            deviceConfig: deviceConfig,
            userConfig: userConfig,
            sessionId: _sessionId,
            apiVersion: config.apiVersion,
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
    /// Fires a server-provided tracking URL verbatim (fire-and-forget GET).
    ///
    /// The engine's tracking URLs are opaque (`…/v1/tracking?e=<encrypted token>`); the SDK
    /// never reconstructs them. `GET /v1/tracking` version-routes on `X-Tracking-Version`
    /// and ignores `X-Decision-Version` — sending the wrong header silently falls back to a
    /// legacy handler that skips Journey completion, so this sends `X-Tracking-Version`.
    public func fireTracking(url: String) {
        // Require an absolute http(s) URL — `URL(string:)` alone accepts relative/scheme-less
        // strings. On failure, log a redacted reason only; NEVER log the URL/query, which
        // carries the sensitive opaque `e=` token.
        guard let parsedURL = URL(string: url),
            let scheme = parsedURL.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            parsedURL.host != nil
        else {
            config.logger.error("Ignoring invalid tracking URL (expected an absolute http(s) URL)")
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
            request.setValue(apiVersion, forHTTPHeaderField: "X-Tracking-Version")
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

    /// Fires a Journey `custom_event` completion beacon once, verbatim.
    ///
    /// Only for `custom_event` completion deals (`creative.tracking.completions[key]`). For
    /// `final_stage` completions there is no URL to fire — the engine records completion at
    /// decision time (check `creative.isJourneyCompletion`).
    ///
    /// Warns (never crashes) when `apiVersion` is unset (the callback would hit the legacy
    /// tracking handler and the completion would silently NOT record — billing-critical), and
    /// when a non-empty `completions` list has no entry matching `key`.
    public func fireCompletion(tracking: Tracking, key: String) {
        if config.apiVersion == nil {
            config.logger.warning(
                "fireCompletion called with no SDKConfig.apiVersion set: the tracking callback will route to the legacy handler and the Journey completion will NOT be recorded. Set apiVersion to the Journey engine version (e.g. \"2025-11-01\")."
            )
        }
        guard let url = tracking.getCompletionUrl(key: key) else {
            if tracking.completions?.isEmpty == false {
                config.logger.warning(
                    "fireCompletion: no completion URL matched key '\(key, privacy: .public)'; nothing was fired."
                )
            }
            return
        }
        fireTracking(url: url)
    }
}
