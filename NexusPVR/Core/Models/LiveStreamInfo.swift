//
//  LiveStreamInfo.swift
//  PVR Client
//
//  Server-side live stream state returned by a keepalive renewal.
//

import Foundation

/// State of the server-side live stream buffer, as reported when the client
/// renews its stream handle.
///
/// `streamDurationMs` / `streamLength` describe the growing timeshift buffer
/// and are what a seekable live-timeshift UI would be built on.
struct LiveStreamInfo: Sendable, Equatable {
    let streamDurationMs: Int64
    let streamLength: Int64
    let isComplete: Bool

    var streamDuration: TimeInterval {
        Double(streamDurationMs) / 1000
    }

    /// Average byte rate of the buffer, used to convert a playback time into the
    /// byte offset NextPVR's `seek` parameter expects. Nil until the buffer holds
    /// enough to give a meaningful ratio.
    var bytesPerSecond: Double? {
        guard streamDuration > 0, streamLength > 0 else { return nil }
        return Double(streamLength) / streamDuration
    }

    /// Byte offset for a given position (seconds from the start of the buffer).
    func byteOffset(forPosition seconds: TimeInterval) -> Int64? {
        guard let bytesPerSecond else { return nil }
        return Int64(max(0, seconds) * bytesPerSecond)
    }
}
