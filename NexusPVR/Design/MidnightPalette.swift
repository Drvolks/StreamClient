//
//  MidnightPalette.swift
//  nextpvr-apple-client
//
//  "Midnight" colour scheme, macOS first. Each colour switches on the
//  system appearance: `light:` is Day, `dark:` is Night.
//

import SwiftUI

enum MidnightPalette {
    // MARK: - Surfaces

    /// Window frame.
    static let shell = Color(light: Color(hex: "#0b1020"), dark: Color(hex: "#0a0e1c"))
    /// App sidebar.
    static let rail = Color(light: Color(hex: "#e7ecf8"), dark: Color(hex: "#070b18"))
    /// Title bar, column heads, detail bar.
    static let railHead = Color(light: Color(hex: "#dde4f4"), dark: Color(hex: "#060a16"))
    /// Structural rules.
    static let line = Color(light: Color(hex: "#b3c0dd"), dark: Color(hex: "#2c3760"))
    /// Row separators.
    static let lineSoft = Color(light: Color(hex: "#d6dded"), dark: Color(hex: "#1b2340"))

    // MARK: - Ink

    static let ink = Color(light: Color(hex: "#0b1020"), dark: Color(hex: "#f4f7ff"))
    static let inkSoft = Color(light: Color(hex: "#3d4a72"), dark: Color(hex: "#aab6e4"))
    static let inkFaint = Color(light: Color(hex: "#4d5a82"), dark: Color(hex: "#8b9ad0"))

    // MARK: - Accent (time / now / primary)

    static let accent = Color(light: Color(hex: "#0b5f74"), dark: Color(hex: "#22d3ee"))
    static let accentSoft = Color(light: Color(hex: "#0b5f74"), dark: Color(hex: "#7ff0ff"))
    /// Text on the accent field.
    static let fieldInk = Color(light: .white, dark: Color(hex: "#04121f"))

    // MARK: - Programme cells

    static let cellRest = Color(light: .white, dark: Color.white.opacity(0.055))
    static let cellRestInk = Color(light: Color(hex: "#0b1020"), dark: Color(hex: "#e6ebff"))
    static let cellRestSub = Color(light: Color(hex: "#3d4a72"), dark: Color(hex: "#a3b0dc"))
    static let cellPast = Color(light: Color(hex: "#0b1020").opacity(0.045), dark: Color.white.opacity(0.018))
    static let cellPastInk = Color(light: Color(hex: "#4d5a82"), dark: Color(hex: "#a3b0dc"))
    /// Selection inverts the ink.
    static let selectedBg = Color(light: Color(hex: "#0b1020"), dark: Color(hex: "#f4f7ff"))
    static let selectedInk = Color(light: Color(hex: "#f4f7ff"), dark: Color(hex: "#0b1020"))
    static let selectedSub = Color(light: Color(hex: "#aab6e4"), dark: Color(hex: "#3d4a72"))

    // MARK: - Controls

    static let inputBg = Color(light: .white, dark: Color.white.opacity(0.06))
    static let hoverTint = Color(light: Color(hex: "#0e7490").opacity(0.10), dark: Color(hex: "#22d3ee").opacity(0.12))
    /// Progress-bar track, hint plate.
    static let barSoft = Color(light: Color(hex: "#0b1020").opacity(0.05), dark: Color.white.opacity(0.07))
    /// Current sidebar item.
    static let navBg = Color(light: Color(hex: "#0b1020"), dark: Color(hex: "#f4f7ff"))
    static let navInk = Color(light: Color(hex: "#f4f7ff"), dark: Color(hex: "#0b1020"))
    /// Toggle knob when on.
    static let chipBg = Color(light: .white, dark: Color(hex: "#7ff0ff"))
    static let chipInk = Color(light: Color(hex: "#0b5f74"), dark: Color(hex: "#04121f"))

    // MARK: - Signals (each one means exactly one thing)

    /// Matches a user topic.
    static let topic = Color(light: Color(hex: "#8a5200"), dark: Color(hex: "#ffc94d"))
    static let topicInk = Color(light: .white, dark: Color(hex: "#2a1c00"))
    /// Destructive actions only.
    static let danger = Color(light: Color(hex: "#b3251a"), dark: Color(hex: "#ff5c47"))
    static let dangerInk = Color(light: .white, dark: Color(hex: "#1a0400"))
}
