//
//  StreamHeaderOverride.swift
//  nextpvr-apple-client
//
//  Hands a renewed access token to streams that are already playing.
//  mpv copies its HTTP headers when a stream opens, so without this a
//  recording longer than the token's lifetime (30 minutes on Dispatcharr)
//  starts getting 401s on every chunk and the player stops.
//
//  Relies on MPVKit's FFmpeg patch 0001 (av_http_set_header_override):
//  each later request that already carries the header gets this value.
//

import Foundation
import Libavformat

nonisolated enum StreamHeaderOverride {
    /// The `Authorization` value later stream requests should carry, or nil
    /// to send whatever the stream was opened with.
    static func setAuthorization(_ value: String?) {
        let result = av_http_set_header_override("Authorization", value)
        if result < 0 {
            print("StreamHeaderOverride: could not set Authorization (\(result))")
        }
    }
}
