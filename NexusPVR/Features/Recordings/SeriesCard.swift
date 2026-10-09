//
//  SeriesCard.swift
//  nextpvr-apple-client
//
//  A series in the macOS and iOS Series index (Midnight): its poster with the
//  unwatched count, then its name and episode counts.
//

#if !os(tvOS)
import SwiftUI

struct SeriesCard: View {
    let summary: RecordingsSeriesSummary
    let posterURL: URL?
    let action: () -> Void

    var body: some View {
        PosterCard(
            title: summary.name,
            meta: counts,
            posterURL: posterURL,
            badge: summary.unwatchedCount > 0 ? "\(summary.unwatchedCount) new" : nil,
            identifier: "series-card-\(summary.name)",
            action: action
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
