//
//  ChannelGridLayout.swift
//  nextpvr-apple-client
//
//  The tvOS Channels grid's "Channels per Row" setting (#177): which column
//  counts are offered, and how much a card's contents grow or shrink with
//  the width that count leaves it.
//

import Foundation

nonisolated enum ChannelGridLayout {
    /// The fixed column counts offered in Settings; nil (Auto) keeps the
    /// adaptive grid.
    static let columnOptions = [2, 3, 4, 5, 6, 8]

    /// The width a card is designed for, about what the adaptive grid gives
    /// it. A card at this width draws at scale 1.
    static let referenceCardWidth: CGFloat = 370

    /// How far a card's contents may shrink or grow. Below the floor the
    /// text stops being readable on a TV; above the ceiling one card would
    /// fill most of the screen's height.
    static let scaleRange: ClosedRange<CGFloat> = 0.6...1.6

    /// A stored preference as a usable column count: nil for Auto and for
    /// anything that isn't one of `columnOptions` (a synced value from a
    /// build with other options).
    static func columns(_ stored: Int?) -> Int? {
        guard let stored, columnOptions.contains(stored) else { return nil }
        return stored
    }

    static func label(_ columns: Int?) -> String {
        guard let columns else { return "Auto" }
        return "\(columns)"
    }

    /// Scale for a card's fonts and metrics in a grid `gridWidth` wide.
    /// Auto, and a grid that hasn't been measured yet, draw at 1.
    static func cardScale(columns: Int?, gridWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        guard let columns, columns > 0, gridWidth > 0 else { return 1 }
        let cardWidth = (gridWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        return min(max(cardWidth / referenceCardWidth, scaleRange.lowerBound), scaleRange.upperBound)
    }
}
