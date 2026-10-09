//
//  PosterCard.swift
//  nextpvr-apple-client
//
//  A poster with a title and a line of facts under it (Midnight, macOS and
//  iOS): the cell of the Series index and of the On Demand library.
//

#if !os(tvOS)
import SwiftUI

struct PosterCard: View {
    let title: String
    let meta: String
    let posterURL: URL?
    /// Chip over the poster's top-right corner, e.g. "3 new".
    var badge: String?
    var placeholderSymbol = "rectangle.stack"
    let identifier: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                poster
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.archivo(15, .extraBold))
                        .textCase(.uppercase)
                        .foregroundStyle(MidnightPalette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(meta)
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
                MidnightFieldChip(text: badge, size: 9)
                    .padding(8)
            }
        }
    }

    private var placeholderGlyph: some View {
        Image(systemName: placeholderSymbol)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(MidnightPalette.plateInk.opacity(0.7))
    }
}
#endif
