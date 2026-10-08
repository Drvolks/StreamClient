//
//  MacWatchStateChip.swift
//  nextpvr-apple-client
//
//  One chip family, three weights: Resume is filled, New is outlined in the
//  accent, Watched is outlined in a quiet rule.
//

#if os(macOS)
import SwiftUI

struct MacWatchStateChip: View {
    let state: RecordingWatchState

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(state.label)
            .midnightBadge(9)
            .foregroundStyle(ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                if case .resume = state {
                    Rectangle().fill(MidnightGradients.field(colorScheme))
                }
            }
            .overlay {
                switch state {
                case .new: Rectangle().strokeBorder(MidnightPalette.accent, lineWidth: 1)
                case .watched: Rectangle().strokeBorder(MidnightPalette.line, lineWidth: 1)
                case .resume: EmptyView()
                }
            }
    }

    private var ink: Color {
        switch state {
        case .resume: MidnightPalette.fieldInk
        case .new: MidnightPalette.accentSoft
        case .watched: MidnightPalette.inkSoft
        }
    }
}
#endif
