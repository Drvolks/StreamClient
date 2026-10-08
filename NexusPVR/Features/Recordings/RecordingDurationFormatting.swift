//
//  RecordingDurationFormatting.swift
//  nextpvr-apple-client
//
//  Formats a stream duration for the recording duration warnings.
//

import Foundation

/// "1h 30m", "45m", "20s": a stream duration in duration warnings.
func formatDuration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    if hours > 0 && minutes > 0 {
        return "\(hours)h \(minutes)m"
    } else if hours > 0 {
        return "\(hours)h"
    } else if minutes > 0 {
        return "\(minutes)m"
    } else {
        return "\(seconds)s"
    }
}
