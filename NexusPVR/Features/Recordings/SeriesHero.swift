//
//  SeriesHero.swift
//  nextpvr-apple-client
//
//  The top of a series page (Midnight, all platforms): the poster on the
//  series' fanart, with how many episodes there are and when the next one
//  records.
//

import SwiftUI

struct SeriesHero: View {
    let summary: RecordingsSeriesSummary
    let posterURL: URL?
    let fanartURL: URL?

    var body: some View {
        PosterHero(posterURL: posterURL, fanartURL: fanartURL) { scale in
            HStack(alignment: .top, spacing: 26 * scale) {
                PosterHeroFact(label: "Recorded", value: "\(summary.completed.count)", scale: scale)
                PosterHeroFact(label: "Unwatched", value: "\(summary.unwatchedCount)", scale: scale)
                if !summary.active.isEmpty {
                    PosterHeroFact(label: "Recording now", value: "\(summary.active.count)", scale: scale)
                }
                if !summary.scheduled.isEmpty {
                    PosterHeroFact(label: "Scheduled", value: "\(summary.scheduled.count)", scale: scale)
                }
            }
            if let next = nextEpisode {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next recording")
                        .midnightKicker(9 * scale)
                        .foregroundStyle(MidnightPalette.accent)
                    Text(next)
                        .midnightMeta(12.5 * scale, weight: .semibold)
                        .foregroundStyle(MidnightPalette.ink)
                }
            }
        }
    }

    /// "S53E13 · Thu, Oct 15 · 9 PM" for the soonest scheduled episode.
    private var nextEpisode: String? {
        guard let next = summary.scheduled.compactMap({ recording in recording.startDate.map { (recording, $0) } })
            .min(by: { $0.1 < $1.1 }) else { return nil }
        var parts: [String] = []
        if let series = next.0.seriesInfo { parts.append(series.shortDisplayString) }
        if let title = next.0.episodeTitle { parts.append(title) }
        parts.append(next.1.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
        parts.append(GuideCellTimeLabel.time(next.1))
        return parts.joined(separator: " · ")
    }
}
