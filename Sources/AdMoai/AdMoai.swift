import Foundation

// MARK: - AdMoai SDK
public struct AdMoai {
    private let client: AdMoaiClient
    public private(set) var config: SDKConfig
    public private(set) var appConfig: AppConfig
    public private(set) var deviceConfig: DeviceConfig
    public private(set) var userConfig: UserConfig
    private let session: URLSession

    public init(
        config: SDKConfig,
        userConfig: UserConfig? = nil
    ) {
        self.config = config
        self.appConfig = .systemDefault()
        self.deviceConfig = .systemDefault()
        self.userConfig = .clear()

        self.client = AdMoaiClient(
            baseURL: config.baseUrl,
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

    // MARK: - SDK Operations
    public func createRequestBuilder() -> DecisionRequestBuilder {
        return DecisionRequestBuilder(
            appConfig: appConfig,
            deviceConfig: deviceConfig,
            userConfig: userConfig
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
        guard let url = URL(string: url) else {
            config.logger.error("Invalid tracking URL: \(url)")
            return
        }
        session.dataTask(with: url).resume()
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
}
