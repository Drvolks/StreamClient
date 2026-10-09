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

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                poster
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.name)
                        .font(.archivo(15, .extraBold))
                        .textCase(.uppercase)
                        .foregroundStyle(MidnightPalette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(counts)
                        .midnightMeta(10.5)
                        .foregroundStyle(MidnightPalette.inkSoft)
                        .lineLimit(2)
                }
                .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(MidnightPalette.cellRest)
            .overlay {
                Rectangle().strokeBorder(isHovering ? MidnightPalette.accent : MidnightPalette.lineSoft,
                                         lineWidth: isHovering ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
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
                MidnightFieldChip(text: "\(summary.unwatchedCount) new", size: 9)
                    .padding(8)
            }
        }
    }

    private var placeholderGlyph: some View {
        Image(systemName: "rectangle.stack")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(MidnightPalette.plateInk.opacity(0.7))
    }

    private var counts: String {
        var parts = ["\(summary.completed.count) recorded"]
        if !summary.active.isEmpty { parts.append("\(summary.active.count) recording") }
        if !summary.scheduled.isEmpty { parts.append("\(summary.scheduled.count) scheduled") }
        return parts.joined(separator: " · ")
    }
}
#endif
