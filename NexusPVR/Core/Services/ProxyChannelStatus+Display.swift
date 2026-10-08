//
//  ProxyChannelStatus+Display.swift
//  nextpvr-apple-client
//
//  Display strings for an active proxy channel, shared by the Status page
//  layouts.
//

import Foundation

extension ProxyChannelStatus {
    /// "H264 / AC3 5.1", or "N/A" when the server reports neither codec.
    var codecSummary: String {
        var parts: [String] = []
        if let videoCodec { parts.append(videoCodec.uppercased()) }
        if let audioCodec {
            var audio = audioCodec.uppercased()
            if let audioChannels { audio += " \(audioChannels)" }
            parts.append(audio)
        }
        return parts.isEmpty ? "N/A" : parts.joined(separator: " / ")
    }

    /// "1h 4m 12s" style elapsed time.
    static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        var result = ""
        if hours > 0 { result += "\(hours)h " }
        if minutes > 0 { result += "\(minutes)m " }
        result += "\(secs)s"
        return result
    }

    /// Data sent so far, in MB below a gigabyte.
    static func dataText(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        return String(format: "%.2f MB", Double(bytes) / (1024 * 1024))
    }
}
