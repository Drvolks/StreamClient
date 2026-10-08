//
//  RecordingSection.swift
//  nextpvr-apple-client
//
//  A titled block of the macOS recordings list: one series, or the
//  one-off recordings (Midnight redesign).
//

import Foundation

nonisolated struct RecordingSection: Identifiable, Equatable {
    static let singlesTitle = "Single recordings"

    let title: String
    let isSeries: Bool
    let recordings: [Recording]

    var id: String { (isSeries ? "series-" : "singles-") + title }

    var totalBytes: Int64 {
        recordings.reduce(0) { $0 + ($1.size ?? 0) }
    }

    /// Series sections in name order, each keeping the incoming order of its
    /// recordings, then the one-off recordings last.
    static func grouped(_ recordings: [Recording]) -> [RecordingSection] {
        var seriesOrder: [String] = []
        var bySeries: [String: [Recording]] = [:]
        var singles: [Recording] = []
        for recording in recordings {
            guard let series = recording.seriesInfo?.seriesName else {
                singles.append(recording)
                continue
            }
            if bySeries[series] == nil { seriesOrder.append(series) }
            bySeries[series, default: []].append(recording)
        }
        var sections = seriesOrder
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { RecordingSection(title: $0, isSeries: true, recordings: bySeries[$0] ?? []) }
        if !singles.isEmpty {
            sections.append(RecordingSection(title: singlesTitle, isSeries: false, recordings: singles))
        }
        return sections
    }

    static func == (lhs: RecordingSection, rhs: RecordingSection) -> Bool {
        lhs.id == rhs.id && lhs.recordings.map(\.id) == rhs.recordings.map(\.id)
    }
}
