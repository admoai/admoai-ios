import Foundation
import UIKit

public func getDeviceDetails() -> DeviceDetails {
    var systemInfo = utsname()
    uname(&systemInfo)
    let modelCode = withUnsafePointer(to: &systemInfo.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in
            String(validatingUTF8: ptr)
        }
    }
    
    return DeviceDetails(
        id: UIDevice.current.identifierForVendor?.uuidString ?? "Unknown",
        model: modelCode ?? UIDevice.current.model,
        manufacturer: "Apple",
        os: UIDevice.current.systemName,
        osVersion: UIDevice.current.systemVersion,
        timezone: TimeZone.current.identifier,
        language: Locale.preferredLanguages.first
    )
}

public struct DeviceDetails {
    public let id: String
    public let model: String
    public let manufacturer: String
    public let os: String
    public let osVersion: String
    public let timezone: String
    public let language: String?
}
