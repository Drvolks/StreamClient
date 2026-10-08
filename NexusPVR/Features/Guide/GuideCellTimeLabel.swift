//
//  GuideCellTimeLabel.swift
//  nextpvr-apple-client
//
//  The time range shown in a guide cell, shortened to fit its width
//  (Midnight redesign, macOS).
//

import Foundation

nonisolated enum GuideCellTimeLabel {
    /// Cells at least this wide get "7:30 AM – 9:00 AM".
    static let fullWidth: CGFloat = 200
    /// Cells at least this wide get "7:30 – 9:00 AM", and keep their badges.
    static let mediumWidth: CGFloat = 132

    /// The range for a cell `width` points wide: both meridiems when it fits,
    /// the end one only when it nearly fits, and none below that.
    static func text(start: Date, end: Date, width: CGFloat, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let full = formatter(withMeridiem: true, locale: locale, timeZone: timeZone)
        let bare = formatter(withMeridiem: false, locale: locale, timeZone: timeZone)
        if width >= fullWidth {
            return "\(full.string(from: start)) – \(full.string(from: end))"
        }
        if width >= mediumWidth {
            return "\(bare.string(from: start)) – \(full.string(from: end))"
        }
        return "\(bare.string(from: start)) – \(bare.string(from: end))"
    }

    /// Whether a cell this wide has room for its NEW / REC / catch-up badges.
    static func showsBadges(width: CGFloat) -> Bool {
        width >= mediumWidth
    }

    /// Short time, with or without the meridiem. 24-hour locales have no
    /// meridiem, so both variants read the same there.
    private static func formatter(withMeridiem: Bool, locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        let template = DateFormatter.dateFormat(fromTemplate: "j:mm", options: 0, locale: locale) ?? "h:mm a"
        formatter.dateFormat = withMeridiem
            ? template
            : template.replacingOccurrences(of: "a", with: "").trimmingCharacters(in: .whitespaces)
        return formatter
    }
}
