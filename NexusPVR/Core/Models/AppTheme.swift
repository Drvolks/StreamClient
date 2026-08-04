//
//  AppTheme.swift
//  nextpvr-apple-client
//
//  Convenience typealias for the appearance override enum (#108). The
//  canonical definition lives inside `UserPreferences` so the tvOS Top
//  Shelf extension (which only shares `UserPreferences.swift` from the
//  Core/Models folder) keeps compiling without needing this sibling file
//  to also be in its membership list.
//

import SwiftUI

typealias AppTheme = UserPreferences.AppTheme

extension AppTheme {
    /// The color scheme to force on the app, or `nil` to follow the device.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    #if os(macOS)
    /// The AppKit appearance to force on the app, or `nil` to follow the
    /// system. Applied alongside `preferredColorScheme` so window chrome and
    /// menus match the chosen theme, not just the SwiftUI content.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
    #endif

    /// SF Symbol shown next to the option in Settings.
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}
