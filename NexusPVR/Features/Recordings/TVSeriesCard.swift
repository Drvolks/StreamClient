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

    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            poster
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.name)
                    .font(.archivo(Theme.scaledFont(19), .extraBold))
                    .textCase(.uppercase)
                    .foregroundStyle(isFocused ? MidnightPalette.selectedInk : MidnightPalette.ink)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text(counts)
                    .midnightMeta(Theme.scaledFont(14))
                    .foregroundStyle(isFocused ? MidnightPalette.selectedSub : MidnightPalette.inkSoft)
                    .lineLimit(1)
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(isFocused ? MidnightPalette.selectedBg : MidnightPalette.cellRest)
        .overlay {
            Rectangle().strokeBorder(isFocused ? MidnightPalette.accent : MidnightPalette.lineSoft,
                                     lineWidth: isFocused ? 4 : 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("series-card-\(summary.name)")
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
                    placeholderGlyph
                }
            } else {
                placeholderGlyph
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipped()
        .overlay(alignment: .topTrailing) {
            if summary.unwatchedCount > 0 {
                MidnightFieldChip(text: "\(summary.unwatchedCount) new", size: Theme.scaledFont(14))
                    .padding(10)
            }
        }
    }

    private var placeholderGlyph: some View {
        Image(systemName: "rectangle.stack")
            .font(.system(size: 44, weight: .semibold))
            .foregroundStyle(Color(hex: "#f4f7ff").opacity(0.7))
    }

    private var counts: String {
        var parts = ["\(summary.completed.count) recorded"]
        if !summary.active.isEmpty { parts.append("\(summary.active.count) recording") }
        if !summary.scheduled.isEmpty { parts.append("\(summary.scheduled.count) scheduled") }
        return parts.joined(separator: " · ")
    }
}
#endif
