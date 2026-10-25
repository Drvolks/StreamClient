//
//  DispatcharrLiveFormat.swift
//  DispatcherPVR
//
//  Turns the Live TV Format setting into the format a channel is asked for
//  (#204). Pure, so the rules can be tested without a client.
//

import Foundation

nonisolated enum DispatcharrLiveFormat {
    /// The concrete format for `choice`.
    ///
    /// - Parameters:
    ///   - onExpensiveNetwork: cellular or personal hotspot, for Auto.
    ///   - serverChoice: what Dispatcharr would pick for this user, for Server
    ///     default; nil when it couldn't be read, which plays MPEG-TS.
    static func resolve(
        _ choice: LiveStreamFormat,
        onExpensiveNetwork: Bool,
        serverChoice: LiveStreamFormat?
    ) -> LiveStreamFormat {
        switch choice {
        case .mpegts, .hls, .fmp4:
            return choice
        case .auto:
            return onExpensiveNetwork ? .hls : .mpegts
        case .serverDefault:
            guard let serverChoice, serverChoice.isConcrete else { return .mpegts }
            return serverChoice
        }
    }

    /// What Dispatcharr would pick: the user's override when it names a
    /// format, else the server default, else MPEG-TS (the server's own
    /// fallback when the setting was never saved).
    static func serverChoice(userOverride: String?, serverDefault: String?) -> LiveStreamFormat {
        format(fromServerValue: userOverride) ?? format(fromServerValue: serverDefault) ?? .mpegts
    }

    /// A format name as Dispatcharr stores it, with the aliases its proxy
    /// accepts (`ts`, `mp4`, `m3u8`).
    static func format(fromServerValue value: String?) -> LiveStreamFormat? {
        switch value?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "mpegts", "ts": .mpegts
        case "fmp4", "mp4": .fmp4
        case "hls", "m3u8": .hls
        default: nil
        }
    }
}
