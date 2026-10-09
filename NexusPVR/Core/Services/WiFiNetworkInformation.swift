// Wi-Fi names are read only to choose a server route; no location fixes are collected.
import Foundation
#if os(iOS)
import SystemConfiguration.CaptiveNetwork
#elseif os(macOS)
import CoreWLAN
#endif
#if !os(tvOS)
import CoreLocation
#endif

nonisolated enum WiFiNetworkInformation {
    /// Only consider Wi-Fi interfaces belonging to the active network path.
    /// Permission denial, unsupported platforms, and unreadable SSIDs return nil.
    static func currentSSID(interfaceNames: [String]) -> String? {
        for name in interfaceNames {
            #if os(iOS)
            if let info = CNCopyCurrentNetworkInfo(name as CFString) as? [String: Any],
               let ssid = info[kCNNetworkInfoKeySSID as String] as? String,
               !ssid.isEmpty {
                return ssid
            }
            #elseif os(macOS)
            if let ssid = CWWiFiClient.shared().interface(withName: name)?.ssid(),
               !ssid.isEmpty {
                return ssid
            }
            #endif
        }
        return nil
    }
}

#if !os(tvOS)
/// Retains the manager for the permission request. Called only by the Settings
/// button, never by API requests or ordinary application startup.
@MainActor
final class WiFiNamePermission: NSObject, CLLocationManagerDelegate {
    static let shared = WiFiNamePermission()
    private let manager = CLLocationManager()

    private override init() {
        super.init()
        manager.delegate = self
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // No cached SSID to invalidate: the next request reads it again.
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }
}
#endif
