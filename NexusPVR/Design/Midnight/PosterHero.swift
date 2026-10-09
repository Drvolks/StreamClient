//
//  PosterHero.swift
//  nextpvr-apple-client
//
//  The top of a title's page (Midnight, all platforms): the poster on the
//  title's fanart, with a few facts beside it. Used by a recorded series
//  and by On Demand movies and series.
//

import SwiftUI

struct PosterHero<Content: View>: View {
    let posterURL: URL?
    let fanartURL: URL?
    /// The facts beside the poster. Receives the platform scale, so its type
    /// can follow the poster's size.
    @ViewBuilder let content: (CGFloat) -> Content

    @Environment(\.colorScheme) private var colorScheme

    /// tvOS draws the same hero larger, for the distance; an iPhone-width
    /// screen draws it smaller so the facts fit beside the poster.
    #if os(tvOS)
    private let scale: CGFloat = Theme.scaledFont(1.7)
    #elseif os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var scale: CGFloat { horizontalSizeClass == .compact ? 0.72 : 1 }
    #else
    private let scale: CGFloat = 1
    #endif

    var body: some View {
        HStack(alignment: .bottom, spacing: 20 * scale) {
            poster
            VStack(alignment: .leading, spacing: 12) {
                content(scale)
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
}
