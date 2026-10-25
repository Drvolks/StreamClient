//
//  DispatcharrAppDataLimits.swift
//  DispatcherPVR
//
//  The `limits` object of `GET /api/accounts/users/me/app-data/` (#199).
//

import Foundation

nonisolated struct DispatcharrAppDataLimits: Decodable, Equatable, Sendable {
    /// Largest value one key may hold, in compact UTF-8 JSON bytes.
    let maxValueBytes: Int
    /// Shared by every app the user runs.
    let maxTotalBytes: Int?
    let maxApps: Int?

    enum CodingKeys: String, CodingKey {
        case maxValueBytes = "max_value_bytes"
        case maxTotalBytes = "max_total_bytes"
        case maxApps = "max_apps"
    }
}
