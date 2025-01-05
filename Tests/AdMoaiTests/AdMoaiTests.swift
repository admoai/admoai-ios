import OSLog
import Testing

@testable import AdMoai

private let baseURL = "http://localhost:8080"

// MARK: - SDK Initialization Tests
@Test
func testSDKInitialization() {
    let config = SDKConfig(
        baseUrl: baseURL,
        logger: Logger(subsystem: "AdMoaiSDK", category: "test")
    )

    let sdk = AdMoai(config: config)

    // Verify default configurations
    #expect(sdk.config.baseUrl == baseURL)
    #expect(sdk.appConfig == .systemDefault())
    #expect(sdk.deviceConfig == .systemDefault())
    #expect(sdk.userConfig == .clear())
}

// MARK: - Configuration Management Tests
@Test
func testAppConfigManagement() {
    let config = SDKConfig(baseUrl: baseURL)
    var sdk = AdMoai(config: config)

    // Test clear
    sdk.clearAppConfig()
    #expect(sdk.appConfig == .clear())

    // Test reset
    sdk.resetAppConfig()
    #expect(sdk.appConfig == .systemDefault())

    // Test custom config
    sdk.setAppConfig(
        name: "TestApp",
        version: "1.0.0",
        buildNumber: "123",
        identifier: "com.test.app",
        language: "en"
    )

    #expect(sdk.appConfig.name == "TestApp")
    #expect(sdk.appConfig.version == "1.0.0")
    #expect(sdk.appConfig.buildNumber == "123")
    #expect(sdk.appConfig.identifier == "com.test.app")
    #expect(sdk.appConfig.language == "en")
}

@Test
func testDeviceConfigManagement() {
    let config = SDKConfig(baseUrl: baseURL)
    var sdk = AdMoai(config: config)

    // Test clear
    sdk.clearDeviceConfig()
    #expect(sdk.deviceConfig == .clear())

    // Test custom config
    sdk.setDeviceConfig(
        id: "device123",
        model: "iPhone14,2",
        manufacturer: "Apple",
        os: "iOS",
        osVersion: "16.0",
        timezone: "UTC",
        language: "en"
    )

    #expect(sdk.deviceConfig.id == "device123")
    #expect(sdk.deviceConfig.model == "iPhone14,2")
    #expect(sdk.deviceConfig.manufacturer == "Apple")
    #expect(sdk.deviceConfig.os == "iOS")
    #expect(sdk.deviceConfig.osVersion == "16.0")
    #expect(sdk.deviceConfig.timezone == "UTC")
    #expect(sdk.deviceConfig.language == "en")
}

@Test
func testUserConfigManagement() {
    let config = SDKConfig(baseUrl: baseURL)
    var sdk = AdMoai(config: config)

    // Test clear
    sdk.clearUserConfig()
    #expect(sdk.userConfig == .clear())

    // Test custom config
    let consent = User.Consent(gdpr: true)

    sdk.setUserConfig(
        id: "user123",
        ip: "192.168.1.1",
        timezone: "America/New_York",
        consent: consent
    )

    #expect(sdk.userConfig.id == "user123")
    #expect(sdk.userConfig.ip == "192.168.1.1")
    #expect(sdk.userConfig.timezone == "America/New_York")
    #expect(sdk.userConfig.consent.gdpr == true)
}
