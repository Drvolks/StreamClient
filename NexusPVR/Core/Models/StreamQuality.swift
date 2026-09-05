//
//  StreamQuality.swift
//  nextpvr-apple-client
//
//  Convenience typealias for the live TV stream quality enum. The canonical
//  definition lives inside `UserPreferences` so the tvOS Top Shelf extension
//  (which only shares `UserPreferences.swift` from the Core/Models folder)
//  keeps compiling without needing this sibling file in its membership list.
//

typealias StreamQuality = UserPreferences.StreamQuality

extension StreamQuality {
    /// Whether this option asks the server to transcode. `.original` streams
    /// the tuner's transport stream directly, which is the only path that
    /// supports the timeshift buffer and its byte-offset seeking.
    nonisolated var isTranscoded: Bool { self != .original }

    /// Profile name passed to `channel.transcode.initiate`. NextPVR names its
    /// stock streaming profiles by resolution — `720p`, `480p` — and Kodi's
    /// addon builds the same string from its resolution setting.
    ///
    /// Nil for `.original`, which never initiates a transcode.
    nonisolated var profileName: String? {
        self == .original ? nil : "\(rawValue)p"
    }

    /// Label shown in Settings.
    nonisolated var label: String {
        self == .original ? "Original" : "\(rawValue)p"
    }

    /// SF Symbol shown next to the option in Settings.
    nonisolated var icon: String {
        switch self {
        case .original: return "tv"
        case .p1080, .p720: return "rectangle.on.rectangle"
        default: return "antenna.radiowaves.left.and.right"
        }
    }

    /// Explanatory text shown under the picker in Settings.
    nonisolated var summary: String {
        switch self {
        case .original:
            return "Streams the broadcast untouched at full bitrate. No load on the server, "
                + "and the only option that supports pausing and seeking live TV."
        case .p1080, .p720:
            return "The server re-encodes live TV to \(rawValue)p, cutting bandwidth at the "
                + "cost of CPU. Needs a server fast enough to transcode in real time."
        default:
            return "The server re-encodes live TV to \(rawValue)p — a large bandwidth saving "
                + "for constrained connections. Pause and seek are unavailable while transcoding."
        }
    }
}
