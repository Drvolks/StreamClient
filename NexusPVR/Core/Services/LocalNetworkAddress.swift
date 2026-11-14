//
//  LocalNetworkAddress.swift
//  PVR Client
//
//  This device's IPv4 address on the local network.
//

import Foundation

/// This device's IPv4 address on the local network, for the Apple TV's
/// temporary log page. Prefers Ethernet/Wi-Fi (`en*`) over other interfaces.
nonisolated enum LocalNetworkAddress {
    static func ipv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var candidates: [(name: String, address: String)] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard let addr = entry.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_RUNNING != 0,
                  flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let address = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard !address.hasPrefix("169.254.") else { continue }
            candidates.append((String(cString: entry.ifa_name), address))
        }
        return preferred(candidates)
    }

    /// en0, then any other en*, then whatever is left.
    static func preferred(_ candidates: [(name: String, address: String)]) -> String? {
        candidates.first { $0.name == "en0" }?.address
            ?? candidates.first { $0.name.hasPrefix("en") }?.address
            ?? candidates.first?.address
    }
}
