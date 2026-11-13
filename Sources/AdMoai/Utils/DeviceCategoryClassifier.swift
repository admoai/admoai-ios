import Foundation

/// The user-interface idiom of the host, platform-neutral so the classifier compiles and is
/// testable on every platform the package builds for (UIKit's own enum is not available on macOS).
enum DeviceIdiom: Sendable, CaseIterable {
    case phone
    case pad
    case mac
    case tv
    case carPlay
    case vision
    case unspecified
}

/// Hardware class first, then idiom (cross-SDK ruling 2026-11-13):
/// - an app running on Mac hardware (an iOS app on a Mac, or a Mac Catalyst app) is `.other`,
///   whatever idiom the system reports for it;
/// - otherwise phone idiom → `.phone`, pad idiom → `.tablet`; Mac, TV, CarPlay and Vision idioms
///   are known other classes → `.other`;
/// - an unspecified idiom is `nil` (absent): no reliable classification is never reported as `.other`.
///
/// `UIDevice.model` is not consulted, so an iPhone-only app on an iPad reports the phone idiom → `.phone`.
func classifyDeviceCategory(idiom: DeviceIdiom, runsOnMac: Bool) -> DeviceCategory? {
    if runsOnMac {
        return .other
    }
    switch idiom {
    case .phone: return .phone
    case .pad: return .tablet
    case .mac, .tv, .carPlay, .vision: return .other
    case .unspecified: return nil
    }
}

/// Whether the process runs on Mac hardware. `ProcessInfo.isiOSAppOnMac` is `false` for a Mac
/// Catalyst app, which usually reports the pad idiom, so both flags are needed.
func hostRunsOnMac(isiOSAppOnMac: Bool, isMacCatalystApp: Bool) -> Bool {
    isiOSAppOnMac || isMacCatalystApp
}
