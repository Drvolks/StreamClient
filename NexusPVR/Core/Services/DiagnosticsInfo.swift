//
//  DiagnosticsInfo.swift
//  PVR Client
//
//  App and device facts written at the top of a shared log.
//

import Foundation

/// App and device facts for the top of a shared log — the hardware model
/// matters when a problem only shows on one device.
nonisolated enum DiagnosticsInfo {
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    static var platformName: String {
        #if os(tvOS)
        return "tvOS"
        #elseif os(macOS)
        return "macOS"
        #else
        return ProcessInfo.processInfo.isiOSAppOnMac ? "iOS app on Mac" : "iOS"
        #endif
    }

    /// Hardware identifier, e.g. "AppleTV14,1" or "iPhone17,2".
    static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (Simulator)"
        }
        #if os(macOS)
        return sysctlString("hw.model") ?? "Mac"
        #else
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return machine.isEmpty ? "unknown" : machine
        #endif
    }

    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let patch = v.patchVersion > 0 ? ".\(v.patchVersion)" : ""
        return "\(platformName) \(v.majorVersion).\(v.minorVersion)\(patch)"
    }

    /// "App / Device / OS / Generated" lines for the top of a shared log.
    static func headerLines(now: Date = Date()) -> [String] {
        [
            "\(Brand.appName) \(appVersion)",
            "Device: \(deviceModel), \(osVersion)",
            "Generated: \(ISO8601DateFormatter().string(from: now))",
        ]
    }

    #if os(macOS)
    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
    #endif
}
