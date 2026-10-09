//
//  CustomHostMode.swift
//  PVR Client
//
//  When the optional custom host replaces the server address (#165).
//

import Foundation

/// When `ServerConfig.customHost` is used instead of `host`.
///
/// iOS and macOS only — tvOS always uses the server address.
nonisolated enum CustomHostMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Only on an expensive network path: cellular on iPhone/iPad, or a personal
    /// hotspot (e.g. a Mac tethered to an iPhone). The server address is used
    /// everywhere else, typically the home LAN.
    case cellularOnly
    /// Every request goes through the custom host.
    case always
    /// Primary address only on the configured Wi-Fi; unknown networks use the custom host.
    case outsideWiFiNetwork

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cellularOnly:
            #if os(macOS)
            return "On iPhone Hotspot"
            #else
            return "On Cellular"
            #endif
        case .always:
            return "Always"
        case .outsideWiFiNetwork:
            return "Outside of Wi-Fi Network"
        }
    }
}
