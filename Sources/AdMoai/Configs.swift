import OSLog

public struct SDKConfig {
    public let baseUrl: String
    public let logger: Logger
    public let sessionConfiguration: URLSessionConfiguration

    /// Initializes the SDKConfig with a base URL, logger, and session configuration.
    public init(
        baseUrl: String,
        logger: Logger = Logger(subsystem: "com.admoai.sdk", category: "AdMoaiSDK"),
        sessionConfiguration: URLSessionConfiguration = defaultSessionConfiguration()
    ) {
        self.baseUrl = baseUrl
        self.logger = logger
        self.sessionConfiguration = sessionConfiguration
        logger.debug("AdMoai SDK config initialized")
    }

    /// Provides the default session configuration with SDK-specific customizations.
    public static func defaultSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = [
            "User-Agent": "AdMoaiSDK/\(sdkVersion)"
        ]
        return configuration
    }

    private static let sdkVersion: String = {
        Bundle(for: AdMoaiClient.self).infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "Unknown"
    }()
}

public protocol Clearable {
    static func clear() -> Self
}

public struct AppConfig: Clearable, Equatable {
    public let name: String?
    public let version: String?
    public let buildNumber: String?
    public let identifier: String?
    public let language: String?

    public init(
        name: String?,
        version: String?,
        buildNumber: String?,
        identifier: String?,
        language: String?
    ) {
        self.name = name
        self.version = version
        self.buildNumber = buildNumber
        self.identifier = identifier
        self.language = language
    }

    public static func clear() -> AppConfig {
        return AppConfig(
            name: nil,
            version: nil,
            buildNumber: nil,
            identifier: nil,
            language: nil
        )
    }

    public static func systemDefault() -> AppConfig {
        let details = getAppDetails()

        return AppConfig(
            name: details.name,
            version: details.version,
            buildNumber: details.buildNumber,
            identifier: details.identifier,
            language: details.language
        )
    }

    public static func == (lhs: AppConfig, rhs: AppConfig) -> Bool {
        return lhs.name == rhs.name && lhs.version == rhs.version
            && lhs.buildNumber == rhs.buildNumber && lhs.identifier == rhs.identifier
            && lhs.language == rhs.language
    }
}

public struct DeviceConfig: Clearable, Equatable {
    public let id: String?
    public let model: String?
    public let manufacturer: String?
    public let os: String?
    public let osVersion: String?
    public let timezone: String?
    public let language: String?

    public init(
        id: String?,
        model: String?,
        manufacturer: String?,
        os: String?,
        osVersion: String?,
        timezone: String?,
        language: String?
    ) {
        self.id = id
        self.model = model
        self.manufacturer = manufacturer
        self.os = os
        self.osVersion = osVersion
        self.timezone = timezone
        self.language = language
    }

    public static func clear() -> DeviceConfig {
        return DeviceConfig(
            id: nil,
            model: nil,
            manufacturer: nil,
            os: nil,
            osVersion: nil,
            timezone: nil,
            language: nil
        )
    }

    public static func systemDefault() -> DeviceConfig {
        let details = getDeviceDetails()

        return DeviceConfig(
            id: details.id,
            model: details.model,
            manufacturer: details.manufacturer,
            os: details.os,
            osVersion: details.osVersion,
            timezone: details.timezone,
            language: details.language
        )
    }

    public static func == (lhs: DeviceConfig, rhs: DeviceConfig) -> Bool {
        return lhs.id == rhs.id && lhs.model == rhs.model && lhs.manufacturer == rhs.manufacturer
            && lhs.os == rhs.os && lhs.osVersion == rhs.osVersion && lhs.timezone == rhs.timezone
            && lhs.language == rhs.language
    }
}

public struct UserConfig: Clearable, Equatable {
    public let id: String?
    public let ip: String?
    public let timezone: String?
    public let consent: User.Consent

    public init(
        id: String?,
        ip: String?,
        timezone: String?,
        consent: User.Consent = User.Consent()
    ) {
        self.id = id
        self.ip = ip
        self.timezone = timezone
        self.consent = consent
    }

    public static func clear() -> UserConfig {
        return UserConfig(
            id: nil,
            ip: nil,
            timezone: nil,
            consent: User.Consent(gdpr: false)
        )
    }

    public static func == (lhs: UserConfig, rhs: UserConfig) -> Bool {
        return lhs.id == rhs.id && lhs.ip == rhs.ip && lhs.timezone == rhs.timezone
            && lhs.consent == rhs.consent
    }
}
