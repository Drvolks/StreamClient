//
//  TVVODEpisodeRow.swift
//  DispatcherPVR
//
//  An episode on a tvOS series page (Midnight): its number and title, when
//  it aired, and how much was watched. Used as the label of a Button styled
//  with TVMidnightButtonStyle; focus inverts the row (#17)
//

#if os(tvOS) && DISPATCHERPVR
import SwiftUI

struct TVVODEpisodeRow: View {
    let episode: VODEpisode
    let watchState: RecordingWatchState
    /// The episode the series page offers to play next.
    var isUpNext = false

    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacingLG) {
            details
            Spacer(minLength: Theme.spacingSM)
            facts
        }
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isFocused ? MidnightPalette.selectedBg : MidnightPalette.cellRest)
        .overlay(alignment: .leading) {
            if isFocused {
                Rectangle().fill(MidnightPalette.accent).frame(width: 6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("vod-episode-\(episode.code ?? String(episode.id))")
    }

    private var subInk: Color {
        isFocused ? MidnightPalette.selectedSub : MidnightPalette.inkSoft
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                if let code = episode.code {
                    Text(code)
                        .midnightMeta(Theme.scaledFont(16), weight: .heavy)
                        .foregroundStyle(isFocused ? MidnightPalette.selectedInk : MidnightPalette.accentSoft)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(isFocused ? MidnightPalette.selectedSub.opacity(0.2) : MidnightPalette.barSoft, in: Theme.badgeShape)
                }
                Text(episode.displayName)
                    .font(.archivo(Theme.scaledFont(23), .extraBold))
                    .foregroundStyle(isFocused ? MidnightPalette.selectedInk : MidnightPalette.ink)
                    .lineLimit(1)
            }
            if let description = episode.description {
                Text(description)
                    .font(.archivo(Theme.scaledFont(18)))
                    .foregroundStyle(subInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 1000, alignment: .leading)
            }
            if case .resume(let progress) = watchState {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(isFocused ? MidnightPalette.selectedSub.opacity(0.25) : MidnightPalette.barSoft)
                        Rectangle()
                            .fill(MidnightGradients.field(colorScheme))
                            .frame(width: geo.size.width * min(max(progress, 0), 1))
                    }
                }
                .frame(width: 420, height: 5)
                .padding(.top, 3)
                .accessibilityLabel("\(Int(progress * 100)) percent watched")
            }
        }
    }

    private var facts: some View {
        VStack(alignment: .trailing, spacing: 8) {
            stateChip
            if !episode.metaLine.isEmpty {
                Text(episode.metaLine)
                    .midnightMeta(Theme.scaledFont(16))
                    .foregroundStyle(subInk)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 150, alignment: .trailing)
    }

    @ViewBuilder
    private var stateChip: some View {
        let size = Theme.scaledFont(14)
        if watchState != .new {
            WatchStateChip(state: watchState, size: size)
        } else if isUpNext {
            Text("Up next")
                .midnightBadge(size)
                .foregroundStyle(isFocused ? MidnightPalette.selectedInk : MidnightPalette.accentSoft)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay {
                    Theme.badgeShape.strokeBorder(isFocused ? MidnightPalette.selectedInk : MidnightPalette.accent, lineWidth: 1)
                }
        }
    }
}
#endif
