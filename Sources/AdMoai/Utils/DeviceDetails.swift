import Foundation

#if canImport(UIKit)
    import UIKit
#endif

public func getDeviceDetails() -> DeviceDetails {
    var systemInfo = utsname()
    uname(&systemInfo)
    let modelCode = withUnsafePointer(to: &systemInfo.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in
            String(validatingUTF8: ptr)
        }
    }

    #if canImport(UIKit)
        return DeviceDetails(
            id: UIDevice.current.identifierForVendor?.uuidString,
            model: modelCode ?? UIDevice.current.model,
            manufacturer: "Apple",
            os: UIDevice.current.systemName,
            osVersion: UIDevice.current.systemVersion,
            timezone: TimeZone.current.identifier,
            language: Locale.preferredLanguages.first,
            category: currentDeviceCategory()
        )
    #elseif os(macOS)
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let osVersionString =
            "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        return DeviceDetails(
            id: nil,
            model: modelCode ?? "Mac",
            manufacturer: "Apple",
            os: "macOS",
            osVersion: osVersionString,
            timezone: TimeZone.current.identifier,
            language: Locale.preferredLanguages.first,
            category: currentDeviceCategory()
        )
    #else
        return DeviceDetails(
            id: nil,
            model: nil,
            manufacturer: nil,
            os: nil,
            osVersion: nil,
            timezone: nil,
            language: nil,
            category: nil
        )
    #endif
}

/// Reads a platform value at most once, on first use, and keeps it for the life of the process.
final class ReadOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    /// `nil` until the first read; then `.some(value)`, even when the value itself is `nil`.
    private var cached: Value?
    private let read: @Sendable () -> Value

    init(_ read: @escaping @Sendable () -> Value) {
        self.read = read
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let value = read()
        cached = value
        return value
    }
}

/// The device category of this process. Neither the hardware class (Mac hardware: an iOS app on a
/// Mac or a Mac Catalyst app)
/// nor the user-interface idiom can change while the process runs, so both are read once, on first
/// use, and reused for every request (cross-SDK ruling 2026-11-13). `UIDevice` belongs to the main
/// actor: the first read happens when the SDK is created (`AdMoai(config:)` reads the device
/// details), which apps do from the main thread at start-up, like every other `UIDevice` read here.
private let processDeviceCategory = ReadOnce<DeviceCategory?> {
    #if canImport(UIKit)
        return classifyDeviceCategory(
            idiom: currentDeviceIdiom(),
            runsOnMac: hostRunsOnMac(
                isiOSAppOnMac: ProcessInfo.processInfo.isiOSAppOnMac,
                isMacCatalystApp: ProcessInfo.processInfo.isMacCatalystApp
            )
        )
    #elseif os(macOS)
        // A Mac is a positively identified desktop.
        return .other
    #else
        return nil
    #endif
}

/// The device category the platform reports for this process (read once; see `processDeviceCategory`).
@Sendable
func currentDeviceCategory() -> DeviceCategory? {
    processDeviceCategory.value
}

#if canImport(UIKit)
    private func currentDeviceIdiom() -> DeviceIdiom {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: return .phone
        case .pad: return .pad
        case .tv: return .tv
        case .carPlay: return .carPlay
        case .mac: return .mac
        case .unspecified: return .unspecified
        #if compiler(>=5.9)
            case .vision: return .vision
        #endif
        @unknown default: return .unspecified
        }
    }
#endif

public struct DeviceDetails {
    public let id: String?
    public let model: String?
    public let manufacturer: String?
    public let os: String?
    public let osVersion: String?
    public let timezone: String?
    public let language: String?
    public let category: DeviceCategory?
}
