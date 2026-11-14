@testable import AdMoai
import Foundation
import Testing

/// The scenarios of `Sources/AdMoai/Utils/DeviceCategoryClassifier.feature`, one test per scenario.
///
/// There is no Gherkin runner in this package, so `everyScenarioHasATest` holds the binding:
/// a scenario added to the feature without a test here, or a test whose scenario was renamed
/// away, fails the build.
struct DeviceCategoryClassifierTests {
    private static let config = SDKConfig(baseUrl: "https://api.mock.admoai.com", apiVersion: "2025-11-01")

    /// A default SDK: device-category collection is off until the app enables it.
    private func makeSDK() -> AdMoai {
        AdMoai(config: Self.config)
    }

    /// An SDK whose app opted in to device-category collection.
    private func collectingSDK() -> AdMoai {
        var sdk = AdMoai(config: Self.config)
        sdk.enableDeviceCategoryCollection()
        return sdk
    }

    private func request(_ sdk: AdMoai) -> DecisionRequestBuilder {
        sdk.createRequestBuilder().addPlacement(key: "home")
    }

    private func device(_ request: DecisionRequest) throws -> [String: Any]? {
        let data = try JSONEncoder().encode(request)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return root["device"] as? [String: Any]
    }

    /// The category the host's platform reports, as the wire string (nil when absent).
    private var systemCategory: String? {
        currentDeviceCategory()?.rawValue
    }

    /// A category source the test moves between requests; no global state, so tests stay parallel.
    private final class Host: @unchecked Sendable {
        private let lock = NSLock()
        private var value: DeviceCategory?
        init(_ value: DeviceCategory?) {
            self.value = value
        }

        func report(_ new: DeviceCategory?) {
            lock.lock(); value = new; lock.unlock()
        }

        var read: @Sendable () -> DeviceCategory? {
            { [self] in lock.lock(); defer { lock.unlock() }; return value }
        }
    }

    private func builder(_ config: DeviceConfig) -> DecisionRequestBuilder {
        DecisionRequestBuilder(appConfig: .clear(), deviceConfig: config, userConfig: .clear())
            .addPlacement(key: "home")
    }

    private func category(_ request: DecisionRequest) throws -> String? {
        try device(request)?["category"] as? String
    }

    static let scenarios: Set<String> = [
        "a phone idiom is a phone",
        "a pad idiom is a tablet",
        "an iPhone-only app on an iPad is a phone",
        "every other known idiom is other",
        "an unspecified idiom leaves the category absent",
        "an iOS app on a Mac is other even with the pad idiom",
        "a Mac Catalyst app is other even with the pad idiom",
        "the default SDK sends no device category",
        "enabling collection sends the platform category",
        "modern iOS has no reliable automatic carrier",
        "clearing the device configuration stops collection",
        "resetting the device configuration collects again",
        "a manual category overrides the system value",
        "a manual category wins over the collected one",
        "a manual category removed by the app stays absent",
        "the platform is read once per process",
        "disabling device collection omits the device object",
        "disabling app collection keeps the device category",
    ]

    @Test func everyScenarioHasATest() throws {
        let feature = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Sources/AdMoai/Utils/DeviceCategoryClassifier.feature")
        let text = try String(contentsOf: feature, encoding: .utf8)
        let titles = text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("Scenario:") }
            .map { $0.dropFirst("Scenario:".count).trimmingCharacters(in: .whitespaces) }
        #expect(Set(titles) == Self.scenarios)
    }

    @Test("a phone idiom is a phone")
    func phoneIdiom() {
        #expect(classifyDeviceCategory(idiom: .phone, runsOnMac: false) == .phone)
    }

    @Test("a pad idiom is a tablet")
    func padIdiom() {
        #expect(classifyDeviceCategory(idiom: .pad, runsOnMac: false) == .tablet)
    }

    @Test("an iPhone-only app on an iPad is a phone")
    func iPhoneAppOnIPad() {
        // The system reports the phone idiom for an iPhone-only app on an iPad, so at this level the
        // input equals `phoneIdiom`'s; the UIDevice → DeviceIdiom mapping itself runs only on a
        // simulator or device (UIKit), so the B5-ios QA runbook covers it on an iPad simulator.
        #expect(classifyDeviceCategory(idiom: .phone, runsOnMac: false) == .phone)
    }

    @Test("every other known idiom is other")
    func everyOtherKnownIdiom() {
        for idiom in [DeviceIdiom.mac, .tv, .carPlay, .vision] {
            #expect(classifyDeviceCategory(idiom: idiom, runsOnMac: false) == .other)
        }
    }

    @Test("an unspecified idiom leaves the category absent")
    func unspecifiedIdiom() {
        #expect(classifyDeviceCategory(idiom: .unspecified, runsOnMac: false) == nil)
    }

    @Test("an iOS app on a Mac is other even with the pad idiom")
    func iOSAppOnMac() {
        for idiom in DeviceIdiom.allCases {
            #expect(classifyDeviceCategory(idiom: idiom, runsOnMac: true) == .other)
        }
    }

    @Test("a Mac Catalyst app is other even with the pad idiom")
    func macCatalystApp() {
        // A Catalyst app reports isiOSAppOnMac == false; isMacCatalystApp identifies it.
        let runsOnMac = hostRunsOnMac(isiOSAppOnMac: false, isMacCatalystApp: true)
        #expect(runsOnMac)
        #expect(classifyDeviceCategory(idiom: .pad, runsOnMac: runsOnMac) == .other)
        #expect(hostRunsOnMac(isiOSAppOnMac: true, isMacCatalystApp: false))
        #expect(!hostRunsOnMac(isiOSAppOnMac: false, isMacCatalystApp: false))
    }

    @Test("the default SDK sends no device category")
    func defaultSendsNoCategory() throws {
        var sdk = makeSDK()
        #expect(sdk.deviceConfig.category == nil)
        #expect(try device(request(sdk).build())?.keys.contains("category") == false)
        #if os(macOS)
            // The host can be classified (a Mac is other), so the absence is the opt-in, not the platform.
            #expect(systemCategory == "other")
        #endif
        sdk.clearDeviceConfig()
        sdk.resetDeviceConfig()
        #expect(try category(request(sdk).build()) == nil, "reset does not start collection")
    }

    @Test("enabling collection sends the platform category")
    func enablingSendsPlatformCategory() throws {
        let sdk = collectingSDK()
        #expect(sdk.deviceConfig.category?.rawValue == systemCategory)
        #expect(try category(request(sdk).build()) == systemCategory)
        #if os(macOS)
            #expect(try category(request(sdk).build()) == "other")
        #endif
    }

    @Test("modern iOS has no reliable automatic carrier")
    func noAutomaticCarrier() {
        let config = collectingSDK().deviceConfig
        #expect(config.carrier == nil)
        #if os(macOS)
            #expect(config.os != nil)
            #expect(config.model != nil)
            #expect(config.category == .other)
        #endif
    }

    @Test("clearing the device configuration stops collection")
    func clearStopsCollection() throws {
        var sdk = collectingSDK()
        sdk.clearDeviceConfig()
        #expect(sdk.deviceConfig.category == nil)
        #expect(try device(request(sdk).build())?["category"] == nil)
    }

    @Test("resetting the device configuration collects again")
    func resetCollectsAgain() throws {
        var sdk = collectingSDK()
        sdk.clearDeviceConfig()
        sdk.resetDeviceConfig()
        #expect(sdk.deviceConfig.category == currentDeviceCategory())
        #expect(try device(request(sdk).build())?["category"] as? String == systemCategory)
    }

    @Test("a manual category overrides the system value")
    func manualOverrides() throws {
        var sdk = makeSDK()
        sdk.setDeviceCategory(.tablet)
        #expect(try device(request(sdk).build())?["category"] as? String == "tablet")
    }

    @Test("a manual category wins over the collected one")
    func manualWinsOverCollected() throws {
        let host = Host(.phone)
        let config = DeviceConfig.systemDefault(categoryProvider: host.read)
            .with(carrier: nil, categoryOverride: .value(.tablet))
        #expect(try category(builder(config).build()) == "tablet")
        host.report(.other)
        #expect(try category(builder(config).build()) == "tablet")
    }

    @Test("a manual category removed by the app stays absent")
    func manualAbsentHasNoFallback() throws {
        let host = Host(.phone)
        let manual = DeviceConfig.systemDefault(categoryProvider: host.read)
            .with(carrier: nil, categoryOverride: .value(.tablet))
        let removed = manual.with(carrier: nil, categoryOverride: .absent)
        #expect(try category(builder(removed).build()) == nil)
        host.report(.other)
        #expect(try category(builder(removed).build()) == nil, "no fallback to the collected value")
        // Through the public API: nil removes it, reset collects again.
        var sdk = collectingSDK()
        sdk.setDeviceCategory(.tablet)
        sdk.setDeviceCategory(nil)
        #expect(try category(request(sdk).build()) == nil)
        sdk.resetDeviceConfig()
        #expect(try category(request(sdk).build()) == systemCategory)
    }

    @Test("the platform is read once per process")
    func platformReadOnce() {
        // `currentDeviceCategory()` serves the process-wide `ReadOnce`; this proves the mechanism by
        // counting reads, including a platform that cannot classify the device (a nil value).
        let reads = Counter()
        let once = ReadOnce<DeviceCategory?> {
            reads.increment()
            return nil
        }
        for _ in 0 ..< 3 {
            #expect(once.value == nil)
        }
        #expect(reads.count == 1)
        let tablet = ReadOnce<DeviceCategory?> {
            reads.increment()
            return .tablet
        }
        #expect(tablet.value == .tablet)
        #expect(tablet.value == .tablet)
        #expect(reads.count == 2)
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() {
            lock.lock(); value += 1; lock.unlock()
        }

        var count: Int {
            lock.lock(); defer { lock.unlock() }; return value
        }
    }

    @Test("disabling device collection omits the device object")
    func disableDeviceOmitsDevice() throws {
        var sdk = makeSDK()
        sdk.setDeviceCategory(.tablet)
        let built = request(sdk).disableDeviceCollection().build()
        #expect(try device(built) == nil)
    }

    @Test("disabling app collection keeps the device category")
    func disableAppKeepsCategory() throws {
        let sdk = collectingSDK()
        let built = request(sdk).disableAppCollection().build()
        #expect(try device(built)?["category"] as? String == systemCategory)
    }
}
