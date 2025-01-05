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
            language: Locale.preferredLanguages.first
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
            language: Locale.preferredLanguages.first
        )
    #else
        return DeviceDetails(
            id: nil,
            model: nil,
            manufacturer: nil,
            os: nil,
            osVersion: nil,
            timezone: nil,
            language: nil
        )
    #endif
}

public struct DeviceDetails {
    public let id: String?
    public let model: String?
    public let manufacturer: String?
    public let os: String?
    public let osVersion: String?
    public let timezone: String?
    public let language: String?
}
