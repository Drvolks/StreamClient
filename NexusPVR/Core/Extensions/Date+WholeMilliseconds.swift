//
//  Date+WholeMilliseconds.swift
//  DispatcherPVR
//
//  Position timestamps are kept to whole milliseconds since 1970, the unit
//  they have in Dispatcharr's app data (#199). A date with a finer fraction
//  would come back from the server a little different and look like a newer
//  entry on every sync.
//

import Foundation

nonisolated extension Date {
    init(millisecondsSince1970 milliseconds: Int64) {
        self.init(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    var millisecondsSince1970: Int64 {
        Int64((timeIntervalSince1970 * 1000).rounded())
    }

    /// This date rounded to the millisecond, exactly as it decodes back from
    /// `millisecondsSince1970`.
    var wholeMilliseconds: Date {
        Date(millisecondsSince1970: millisecondsSince1970)
    }
}
