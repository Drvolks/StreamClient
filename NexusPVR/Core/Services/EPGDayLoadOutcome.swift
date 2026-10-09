//
//  EPGDayLoadOutcome.swift
//  PVR Client
//
//  Result of asking a backend for one day of EPG (#157).
//

import Foundation

nonisolated enum EPGDayLoadOutcome: Sendable {
    /// The day's listings are in the cache.
    case loaded
    /// The request failed; the cache is unchanged and the day can be retried.
    case failed
    /// The backend can't serve a single day — only the full EPG.
    case unsupported
}
