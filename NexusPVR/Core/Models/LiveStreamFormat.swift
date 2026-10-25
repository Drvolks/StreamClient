//
//  LiveStreamFormat.swift
//  DispatcherPVR
//
//  How Dispatcharr delivers live TV to this app (#193). Sent explicitly as
//  `?output_format=` on servers that have HLS output, so a server default or
//  a per-user override doesn't change what the app gets.
//

import Foundation

nonisolated enum LiveStreamFormat: String, Codable, CaseIterable, Sendable {
    /// One continuous transport stream: what the app has always played.
    case mpegts
    /// Short segments listed in a playlist the player polls.
    case hls

    var label: String {
        switch self {
        case .mpegts: "MPEG-TS"
        case .hls: "HLS"
        }
    }

    var summary: String {
        switch self {
        case .mpegts:
            "One continuous stream: the shortest delay behind live and the fastest channel changes. Best at home."
        case .hls:
            "Short segments fetched every few seconds: copes better with cellular, roaming and reverse proxies, "
                + "but runs about 10 to 15 seconds behind live. Applies to the next channel you play."
        }
    }
}
