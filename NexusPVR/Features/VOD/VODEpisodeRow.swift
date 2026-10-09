//
//  VODEpisodeRow.swift
//  DispatcherPVR
//
//  An episode on a series page (Midnight, macOS and iOS): its number and
//  title, when it aired and how long it runs, and how much was watched (#17)
//

#if !os(tvOS) && DISPATCHERPVR
import SwiftUI

struct VODEpisodeRow: View {
    let episode: VODEpisode
    let watchState: RecordingWatchState
    /// The episode the series page offers to play next.
    var isUpNext = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                if let code = episode.code {
                    Text(code)
                        .midnightMeta(10.5, weight: .heavy)
                        .foregroundStyle(MidnightPalette.accentSoft)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(MidnightPalette.barSoft)
                        .fixedSize()
                }
                Text(episode.displayName)
                    .font(.archivo(15.5, .extraBold))
                    .foregroundStyle(MidnightPalette.ink)
                    .lineLimit(1)
                Spacer(minLength: 6)
                stateChip.fixedSize()
            }
            if !episode.metaLine.isEmpty {
                Text(episode.metaLine)
                    .midnightMeta(11)
                    .foregroundStyle(MidnightPalette.inkSoft)
                    .lineLimit(1)
            }
            if let description = episode.description {
                Text(description)
                    .font(.archivo(13))
                    .foregroundStyle(MidnightPalette.inkSoft)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            if case .resume(let progress) = watchState {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(MidnightPalette.barSoft)
                        Rectangle()
                            .fill(MidnightGradients.field(colorScheme))
                            .frame(width: geo.size.width * min(max(progress, 0), 1))
                    }
                }
                .frame(height: 3)
                .frame(maxWidth: 420)
                .padding(.top, 2)
                .accessibilityLabel("\(Int(progress * 100)) percent watched")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? MidnightPalette.hoverTint : .clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MidnightPalette.lineSoft).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("vod-episode-\(episode.code ?? String(episode.id))")
    }

    @ViewBuilder
    private var stateChip: some View {
        if watchState != .new {
            WatchStateChip(state: watchState)
        } else if isUpNext {
            Text("Up next")
                .midnightBadge(9)
                .foregroundStyle(MidnightPalette.accentSoft)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .overlay { Rectangle().strokeBorder(MidnightPalette.accent, lineWidth: 1) }
        }
    }
}
#endif
