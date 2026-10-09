//
//  TVSeriesCard.swift
//  nextpvr-apple-client
//
//  A series in the tvOS Series grid (Midnight): its poster with the
//  unwatched count, then its name and episode counts. Used as the label of
//  a Button styled with TVMidnightButtonStyle; focus draws an accent frame.
//

#if os(tvOS)
import SwiftUI

struct TVSeriesCard: View {
    let summary: RecordingsSeriesSummary
    let posterURL: URL?

    var body: some View {
        TVPosterCard(
            title: summary.name,
            meta: counts,
            posterURL: posterURL,
            badge: summary.unwatchedCount > 0 ? "\(summary.unwatchedCount) new" : nil,
            identifier: "series-card-\(summary.name)"
        )
    }

    private var counts: String {
        var parts = ["\(summary.completed.count) recorded"]
        if !summary.active.isEmpty { parts.append("\(summary.active.count) recording") }
        if !summary.scheduled.isEmpty { parts.append("\(summary.scheduled.count) scheduled") }
        return parts.joined(separator: " · ")
    }
}
#endif
