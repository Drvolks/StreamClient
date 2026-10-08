//
//  MidnightTypography.swift
//  nextpvr-apple-client
//
//  The Midnight type roles. Tracking is specified in em, so it scales with
//  the size.
//

import SwiftUI

extension View {
    /// Page and pane titles: Archivo 800, uppercase, tight.
    func midnightDisplay(_ size: CGFloat) -> some View {
        font(.archivo(size, .extraBold))
            .tracking(-0.02 * size)
            .textCase(.uppercase)
    }

    /// Small labels above titles ("GUIDE", "CATEGORY 03"): Archivo 800,
    /// uppercase, wide.
    func midnightKicker(_ size: CGFloat = 10.5) -> some View {
        font(.archivo(size, .extraBold))
            .tracking(0.18 * size)
            .textCase(.uppercase)
    }

    /// Badges (LIVE, NEW, topic tags): Archivo 800, uppercase.
    func midnightBadge(_ size: CGFloat = 9) -> some View {
        font(.archivo(size, .extraBold))
            .tracking(0.14 * size)
            .textCase(.uppercase)
    }

    /// Times, numbers and sizes, so they line up in columns.
    func midnightMeta(_ size: CGFloat = 11, weight: Font.Weight = .regular) -> some View {
        font(.system(size: size, weight: weight, design: .monospaced))
    }
}
