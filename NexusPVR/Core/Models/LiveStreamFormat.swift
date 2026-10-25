//
//  LiveStreamFormat.swift
//  DispatcherPVR
//
//  How Dispatcharr delivers live TV to this app (#193, #79, #204). The
//  concrete formats are sent explicitly as `?output_format=` on servers that
//  have HLS output, so a server default or a per-user override doesn't change
//  what the app gets; Auto and Server default resolve to one of them when a
//  channel starts (`DispatcharrLiveFormat.resolve`).
//

import Foundation

nonisolated enum LiveStreamFormat: String, Codable, CaseIterable, Sendable {
    /// One continuous transport stream: what the app has always played.
    case mpegts
    /// Short segments listed in a playlist the player polls.
    case hls
    /// One continuous fragmented-MP4 stream, remuxed by Dispatcharr (#79).
    case fmp4
    /// MPEG-TS, or HLS on cellular and personal hotspot (#204).
    case auto
    /// Whatever Dispatcharr would pick for this user: their Output Format
    /// override, else the server default (#204).
    case serverDefault = "server"

    /// The formats Dispatcharr can be asked for, as opposed to the choices
    /// that resolve to one of them.
    var isConcrete: Bool {
        switch self {
        case .mpegts, .hls, .fmp4: true
        case .auto, .serverDefault: false
        }
    }

    var label: String {
        switch self {
        case .mpegts: "MPEG-TS"
        case .hls: "HLS"
        case .fmp4: "fMP4"
        case .auto: "Auto"
        case .serverDefault: "Server default"
        }
    }

    var summary: String {
        switch self {
        case .mpegts:
            "One continuous stream: the shortest delay behind live and the fastest channel changes. Best at home."
        case .hls:
            "Short segments fetched every few seconds: copes better with cellular, roaming and reverse proxies, "
                + "but runs about 10 to 15 seconds behind live. Applies to the next channel you play."
        case .fmp4:
            "One continuous fragmented-MP4 stream, repackaged by Dispatcharr from the same source. Plays like "
                + "MPEG-TS; useful when something between the server and this device handles MP4 better."
        case .auto:
            "MPEG-TS on Wi-Fi and Ethernet, HLS on cellular and personal hotspot. Chosen each time a channel starts."
        case .serverDefault:
            "Follows Dispatcharr: your Output Format override if you have one, otherwise the server's default."
        }
    }
}
