//
//  SettingsCategory.swift
//  nextpvr-apple-client
//
//  The eight categories of the macOS Settings index (Midnight redesign).
//

import Foundation

nonisolated enum SettingsCategory: Int, CaseIterable, Identifiable {
    case server
    case general
    case playback
    case subtitles
    case guide
    case recordings
    case advanced
    case about

    var id: Int { rawValue }

    /// Two-digit position shown in the index, "01" to "08".
    var number: String {
        String(format: "%02d", rawValue + 1)
    }

    var title: String {
        switch self {
        case .server: "Server"
        case .general: "General"
        case .playback: "Playback"
        case .subtitles: "Subtitles"
        case .guide: "Guide"
        case .recordings: "Recordings"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    /// The one hint shown under the category's rows. Playback swaps this for
    /// the selected stream setting's own explanation, which can warn that it
    /// is unavailable.
    var hint: String {
        switch self {
        case .server:
            "The \(Brand.serverName) server this device talks to. Unlinking forgets it on this "
                + "device only — nothing changes on the server."
        case .general:
            "Landing Page is what opens at launch. Theme overrides the device appearance; "
                + "System follows it."
        case .playback:
            "Seek and audio settings apply to the next stream you play."
        case .subtitles:
            "Manual asks you each time from the player panel. Auto picks the last subtitle "
                + "language you used whenever the stream carries it."
        case .guide:
            "Only the groups and profiles you tick appear in the sidebar. Everything else "
                + "stays one click away under All Channels."
        case .recordings:
            "Hiding recording features removes every recording menu, button and tab across "
                + "the app. Scheduled recordings keep running on the server."
        case .advanced:
            "The defaults suit almost every setup. Change these only when a specific channel "
                + "misbehaves — both apply to the next stream you play."
        case .about:
            "Include this version when you report a problem."
        }
    }
}
