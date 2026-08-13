//
//  UIFontSize.swift
//  nextpvr-apple-client
//
//  User-selectable tvOS UI font size (issue #107).
//
//  Apple TV users sit anywhere from 6 to 20 feet from the screen, and
//  the hardcoded 28pt body font that looks fine on a 65" display
//  becomes unreadable on an 85" one. This enum exposes a four-step
//  scaling preference that callers apply to the Theme's tv* font
//  constants at the call site:
//
//      Text("Foo").font(.tvBody(uiFontSize))
//      Text("Foo").font(.tvSidebar(uiFontSize))
//
//  Default is `.medium`, which preserves the visual output of the
//  pre-feature build exactly — existing users see zero change on
//  first launch after upgrade.
//
//  Mirrors the SubtitleSize pattern (Core/Models/SubtitleSize.swift):
//  raw enum, Codable, CaseIterable, Foundation-only — so the model
//  layer can be unit-tested without SwiftUI, UIKit, or Xcode.
//

import Foundation

enum UIFontSize: String, Codable, CaseIterable {
    case small
    case medium
    case large
    case xLarge

    /// The user-facing label shown in the Settings picker.
    var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .xLarge: return "X-Large"
        }
    }

    /// Multiplier applied to Theme's hardcoded tv* font constants.
    /// `medium` (1.0) is the de facto baseline so default behavior
    /// is unchanged.
    ///
    /// The curve is non-linear (matches Apple TV's own "Text Size"
    /// curve roughly): each step is roughly 15% larger than the
    /// previous one, with `xLarge` only going 30% above baseline so
    /// the sidebar still fits.
    var scale: Double {
        switch self {
        case .small: return 0.85
        case .medium: return 1.0
        case .large: return 1.15
        case .xLarge: return 1.3
        }
    }

    /// Multiplier for the tvOS sidebar / menu.
    ///
    /// Steeper than `scale` on purpose. The sidebar baseline is small
    /// enough that the shared curve made changing the setting look like it
    /// had barely touched the menu; this spreads the four steps wider so
    /// the difference is obvious from across the room. X-Large lands the
    /// sidebar above its pre-#107 size, which is the point — that's the
    /// step for people who couldn't read the menu before. (#107)
    var sidebarScale: Double {
        switch self {
        case .small: return 0.8
        case .medium: return 1.0
        case .large: return 1.25
        case .xLarge: return 1.5
        }
    }

    /// Multiplier for the tvOS layout metrics that have to hold scaled
    /// text — guide row height, channel icons, the channel name column.
    /// Deliberately *not* applied to the guide's hour column: widening
    /// the time axis would show less of the schedule rather than fixing
    /// a clipping problem. (#107)
    var layoutScale: Double { scale }
}
