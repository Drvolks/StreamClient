//
//  TVPosterCard.swift
//  nextpvr-apple-client
//
//  A poster with a title and a line of facts under it (Midnight, tvOS): the
//  cell of the Series grid and of the On Demand library. Used as the label
//  of a Button styled with TVMidnightButtonStyle; focus draws an accent frame.
//

#if os(tvOS)
import SwiftUI

struct TVPosterCard: View {
    let title: String
    let meta: String
    let posterURL: URL?
    /// Chip over the poster's top-right corner, e.g. "3 new".
    var badge: String?
    var placeholderSymbol = "rectangle.stack"
    let identifier: String

    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            poster
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.archivo(Theme.scaledFont(19), .extraBold))
                    .textCase(.uppercase)
                    .foregroundStyle(isFocused ? MidnightPalette.selectedInk : MidnightPalette.ink)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text(meta)
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
        .accessibilityIdentifier(identifier)
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
            if let badge {
                MidnightFieldChip(text: badge, size: Theme.scaledFont(14))
                    .padding(10)
            }
        }
    }

    private var placeholderGlyph: some View {
        Image(systemName: placeholderSymbol)
            .font(.system(size: 44, weight: .semibold))
            .foregroundStyle(MidnightPalette.plateInk.opacity(0.7))
    }
}
#endif
