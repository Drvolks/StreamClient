//
//  MidnightGradients.swift
//  nextpvr-apple-client
//
//  The Midnight gradients. A gradient can't switch on appearance the way a
//  `Color(light:dark:)` does, so each one takes the environment's
//  `ColorScheme`. All of them run at the prototype's 158° angle.
//

import SwiftUI

enum MidnightGradients {
    private static let start = UnitPoint(x: 0.3, y: 0)
    private static let end = UnitPoint(x: 0.7, y: 1)

    /// Content background behind the grid and panes.
    static func ground(_ scheme: ColorScheme) -> LinearGradient {
        let stops: [Gradient.Stop] = scheme == .dark
            ? [
                .init(color: Color(hex: "#0b1020"), location: 0),
                .init(color: Color(hex: "#141d3a"), location: 0.62),
                .init(color: Color(hex: "#0a0e1c"), location: 1)
            ]
            : [
                .init(color: Color(hex: "#fbfcff"), location: 0),
                .init(color: Color(hex: "#e9eefb"), location: 0.62),
                .init(color: Color(hex: "#f5f7fe"), location: 1)
            ]
        return LinearGradient(stops: stops, startPoint: start, endPoint: end)
    }

    /// The accent field: pane headers, the selected category, the "Now" pill,
    /// live cells, primary buttons, toggles that are on, progress fills.
    static func field(_ scheme: ColorScheme) -> LinearGradient {
        let colors: [Color] = scheme == .dark
            ? [Color(hex: "#22d3ee"), Color(hex: "#2563eb")]
            : [Color(hex: "#0e7490"), Color(hex: "#1e3a8a")]
        return LinearGradient(colors: colors, startPoint: start, endPoint: end)
    }

    /// Ground for channel logos (guide column, channel-card band). Flat on
    /// Night; on Day it matches `field`, because logos are mostly
    /// white-on-transparent and need a dark ground.
    static func channelPlate(_ scheme: ColorScheme) -> LinearGradient {
        scheme == .dark
            ? LinearGradient(colors: [Color(hex: "#060a16")], startPoint: start, endPoint: end)
            : field(scheme)
    }
}
