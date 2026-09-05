//
//  TranscodeProgress.swift
//  PVR Client
//
//  Progress of a server-side live TV transcode, as reported by
//  NextPVR's `channel.transcode.status` method.
//

import Foundation

/// Startup progress of a `channel.transcode.initiate` request.
///
/// NextPVR counts `percentage` to 100 while it starts ffmpeg and fills the
/// first HLS segments; the playlist is only playable once it gets there.
/// `isFinal` means the server has stopped making progress, so a final
/// document short of 100 is a failed transcode rather than a slow one.
nonisolated struct TranscodeProgress: Sendable, Equatable {
    let percentage: Int
    let isFinal: Bool

    /// The transcode is running and the playlist can be opened.
    var isReady: Bool { percentage >= 100 }

    /// The server gave up before the stream became playable.
    var hasFailed: Bool { isFinal && percentage < 100 }
}
