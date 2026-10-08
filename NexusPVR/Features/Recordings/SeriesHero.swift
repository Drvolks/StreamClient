//
//  SeriesHero.swift
//  nextpvr-apple-client
//
//  The top of a series page (Midnight, macOS and tvOS): the poster on the
//  series' fanart, with how many episodes there are and when the next one
//  records.
//

#if os(macOS) || os(tvOS)
import SwiftUI

struct SeriesHero: View {
    let summary: RecordingsSeriesSummary
    let posterURL: URL?
    let fanartURL: URL?

    @Environment(\.colorScheme) private var colorScheme

    /// tvOS draws the same hero larger, for the distance.
    #if os(tvOS)
    private let scale: CGFloat = Theme.scaledFont(1.7)
    #else
    private let scale: CGFloat = 1
    #endif

    var body: some View {
        HStack(alignment: .bottom, spacing: 20 * scale) {
            poster
            VStack(alignment: .leading, spacing: 12) {
                facts
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
            .padding(.bottom, 4)
            Spacer(minLength: 0)
        }
        .padding(18 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { backdrop }
        .overlay { Rectangle().strokeBorder(MidnightPalette.lineSoft, lineWidth: 1) }
        .clipped()
    }

    private var poster: some View {
        ZStack {
            Rectangle().fill(MidnightGradients.channelPlate(colorScheme))
            if let posterURL {
                CachedAsyncImage(url: posterURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ProgressView()
                } fallback: {
                    EmptyView()
                }
            }
        }
        .frame(width: 130 * scale, height: 195 * scale)
        .clipped()
        .overlay { Rectangle().strokeBorder(MidnightPalette.line, lineWidth: 1) }
    }

    /// The fanart, dimmed and faded into the page so the text stays readable.
    @ViewBuilder
    private var backdrop: some View {
        ZStack {
            MidnightPalette.cellRest
            if let fanartURL {
                CachedAsyncImage(url: fanartURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                } fallback: {
                    Color.clear
                }
                .opacity(colorScheme == .dark ? 0.35 : 0.22)
            }
            LinearGradient(
                colors: [MidnightPalette.shell.opacity(colorScheme == .dark ? 0.85 : 0.0), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var facts: some View {
        HStack(alignment: .top, spacing: 26 * scale) {
            fact("Recorded", summary.completed.count)
            fact("Unwatched", summary.unwatchedCount)
            if !summary.active.isEmpty { fact("Recording now", summary.active.count) }
            if !summary.scheduled.isEmpty { fact("Scheduled", summary.scheduled.count) }
        }
    }

    private func fact(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.archivo(30 * scale, .extraBold))
                .foregroundStyle(MidnightPalette.ink)
            Text(label)
                .midnightKicker(9 * scale)
                .foregroundStyle(MidnightPalette.inkSoft)
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
#endif
