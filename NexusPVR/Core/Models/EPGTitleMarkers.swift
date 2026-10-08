//
//  EPGTitleMarkers.swift
//  nextpvr-apple-client
//
//  Superscript markers some EPG sources append to program titles, such as
//  "ᴺᵉʷ" and "ᴸᶦᵛᵉ". They read as odd text, so titles shown in the UI strip
//  them and the app draws a NEW or LIVE badge instead.
//

import Foundation

nonisolated enum EPGTitleMarkers {
    /// "ᴺᵉʷ".
    static let new = "\u{1D3A}\u{1D49}\u{02B7}"

    /// "ᴸᶦᵛᵉ", tolerating the capital / small-letter variants of each
    /// superscript letter that sources mix (ᴵ ᶦ ⁱ, ⱽ ᵛ, ᴱ ᵉ).
    private static let livePattern = "\u{1D38}[\u{1D35}\u{1DA6}\u{2071}][\u{2C7D}\u{1D5B}][\u{1D31}\u{1D49}]"

    /// Whether `title` carries the "ᴸᶦᵛᵉ" marker: the program airs live.
    static func isLive(_ title: String) -> Bool {
        title.range(of: livePattern, options: .regularExpression) != nil
    }

    /// `title` without its NEW and LIVE markers or the spacing around them.
    static func clean(_ title: String) -> String {
        title
            .replacingOccurrences(of: "\\s*(\(new)|\(livePattern))\\s*", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
