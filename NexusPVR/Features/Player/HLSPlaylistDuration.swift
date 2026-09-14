//
//  HLSPlaylistDuration.swift
//  nextpvr-apple-client
//
//  Sums the segment durations of an HLS media playlist (issue #171).
//

import Foundation

/// The playlist is server-controlled and polled repeatedly while an in-progress
/// recording plays, so a truncated or malformed response (e.g. a partial write at
/// the playlist tail) must be skipped rather than trusted.
nonisolated enum HLSPlaylistDuration {
    /// Total of all parseable `#EXTINF:<duration>,[title]` entries, in seconds.
    /// Lines with a missing or non-numeric duration are ignored.
    static func totalSeconds(in playlist: String) -> Double {
        var total: Double = 0
        for line in playlist.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#EXTINF:") else { continue }
            let segPart = trimmed.dropFirst("#EXTINF:".count)
            guard let first = segPart.split(separator: ",", omittingEmptySubsequences: false).first,
                  let d = Double(first.trimmingCharacters(in: .whitespaces)) else { continue }
            total += d
        }
        return total
    }
}
