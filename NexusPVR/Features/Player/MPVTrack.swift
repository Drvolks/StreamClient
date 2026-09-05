//
//  MPVTrack.swift
//  nextpvr-apple-client
//
//  MPV track model for audio/video/subtitle selection
//

import Foundation

nonisolated struct MPVTrack: Identifiable, Equatable {
    let id: Int
    let type: String       // "video", "audio", "sub"
    let title: String?
    let lang: String?
    let codec: String?
    let channels: String?  // audio only
    let bitrate: Int?      // demux-bitrate
    let isSelected: Bool
    /// Audio description track for visually impaired viewers (DVB audio_type 3,
    /// ffmpeg AV_DISPOSITION_VISUAL_IMPAIRED). mpv exposes this flag but does
    /// not consider it when auto-selecting, so the app has to.
    var isVisualImpaired: Bool = false
    /// Hearing-impaired audio (DVB audio_type 2, AV_DISPOSITION_HEARING_IMPAIRED).
    var isHearingImpaired: Bool = false

    /// True for accessibility tracks that should not be chosen automatically
    /// when a regular track is available.
    var isAccessibilityTrack: Bool { isVisualImpaired || isHearingImpaired }

    var displayName: String {
        var parts: [String] = []
        if let lang = lang, !lang.isEmpty {
            parts.append(Locale.current.localizedString(forLanguageCode: lang) ?? lang)
        }
        if let title = title, !title.isEmpty {
            parts.append(title)
        }
        if parts.isEmpty {
            parts.append("Track \(id)")
        }
        if isVisualImpaired {
            parts.append("Audio Description")
        } else if isHearingImpaired {
            parts.append("Hearing Impaired")
        }
        return parts.joined(separator: " - ")
    }

    /// Returns the id of the audio track to switch to when mpv's automatic
    /// selection landed on an accessibility track (audio description or
    /// hearing-impaired mix) while a regular track exists, or nil when the
    /// current selection should be left alone.
    ///
    /// mpv 0.41 ranks audio tracks by default flag, then lowest id, and never
    /// looks at the impaired flags. DVB broadcasters often list the audio
    /// description stream first, so this is needed to get the main mix.
    static func regularAudioTrackToSelect(in tracks: [MPVTrack]) -> Int? {
        let audio = tracks.filter { $0.type == "audio" }
        guard let selected = audio.first(where: { $0.isSelected }),
              selected.isAccessibilityTrack else { return nil }
        let regular = audio.filter { !$0.isAccessibilityTrack }
        // Prefer a regular track in the same language as the one mpv picked,
        // otherwise the first regular track in stream order.
        let sameLang = regular.first { $0.lang == selected.lang }
        return (sameLang ?? regular.first)?.id
    }

    var audioDetail: String {
        var parts: [String] = []
        if let codec = codec { parts.append(codec.uppercased()) }
        if let ch = channels, let n = Int(ch) {
            switch n {
            case 1: parts.append("Mono")
            case 2: parts.append("Stereo")
            case 6: parts.append("5.1")
            case 8: parts.append("7.1")
            default: parts.append("\(n)ch")
            }
        }
        if let br = bitrate, br > 0 {
            parts.append("\(br / 1000) kbps")
        }
        return parts.joined(separator: " · ")
    }
}
