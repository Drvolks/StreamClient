//
//  GuideCellTimeLabel.swift
//  nextpvr-apple-client
//
//  Program start and end times as the macOS guide and channel cards show
//  them (Midnight redesign). Times on the hour drop their minutes, so a range
//  reads "10 AM – 11 AM" or "10 AM – 10:30 AM".
//

import Foundation

nonisolated enum GuideCellTimeLabel {
    /// Width a caller passes to always get the full form.
    static let fullWidth: CGFloat = 200
    /// Cells narrower than this drop the meridiems ("10 – 10:30") and their
    /// badges.
    static let mediumWidth: CGFloat = 132

    /// The range for a cell `width` points wide.
    static func text(start: Date, end: Date, width: CGFloat, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let withMeridiem = width >= mediumWidth
        let startText = time(start, withMeridiem: withMeridiem, locale: locale, timeZone: timeZone)
        let endText = time(end, withMeridiem: withMeridiem, locale: locale, timeZone: timeZone)
        return "\(startText) – \(endText)"
    }

    /// One time: "10 AM" on the hour, "10:30 AM" otherwise. 24-hour locales
    /// always keep the minutes ("10:00"), since a bare "10" reads ambiguously.
    static func time(_ date: Date, withMeridiem: Bool = true, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let hourTemplate = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "h a"
        let uses12Hour = hourTemplate.contains("a")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let onTheHour = calendar.component(.minute, from: date) == 0

        var format = uses12Hour && onTheHour
            ? hourTemplate
            : DateFormatter.dateFormat(fromTemplate: "j:mm", options: 0, locale: locale) ?? "h:mm a"
        if !withMeridiem {
            format = format.replacingOccurrences(of: "a", with: "").trimmingCharacters(in: .whitespaces)
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// Whether a cell this wide has room for its NEW / REC / catch-up badges.
    static func showsBadges(width: CGFloat) -> Bool {
        width >= mediumWidth
    }
}
