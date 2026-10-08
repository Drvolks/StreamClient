//
//  RetryAfter.swift
//  nextpvr-apple-client
//
//  How long a rate-limited (HTTP 429) server asked us to wait, from its
//  `Retry-After` header: delay seconds or an HTTP date.
//

import Foundation

nonisolated enum RetryAfter {
    /// Used when the server gives no (or an unreadable) Retry-After.
    static let defaultDelay: TimeInterval = 60
    /// Never wait longer than this, whatever the server says.
    static let maximumDelay: TimeInterval = 15 * 60

    static func delay(from header: String?, now: Date = Date()) -> TimeInterval {
        guard let value = header?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return defaultDelay
        }
        if let seconds = TimeInterval(value) {
            return min(max(seconds, 1), maximumDelay)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: value) {
            return min(max(date.timeIntervalSince(now), 1), maximumDelay)
        }
        return defaultDelay
    }
}
