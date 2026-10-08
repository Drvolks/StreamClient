//
//  WatchStateChip.swift
//  nextpvr-apple-client
//
//  One chip family, three weights: Resume is filled, New is outlined in the
//  accent, Watched is outlined in a quiet rule. macOS and tvOS (Midnight).
//

#if os(macOS) || os(tvOS)
import SwiftUI

struct WatchStateChip: View {
    let state: RecordingWatchState
    var size: CGFloat = 9

    @Environment(\.colorScheme) private var colorScheme
    #if os(tvOS)
    /// Inside a focused (inverted) tvOS row, the outlined chips take the
    /// row's dark ink; the accent would be too faint on the light plate.
    @Environment(\.isFocused) private var isFocused
    #else
    private let isFocused = false
    #endif

    var body: some View {
        Text(state.label)
            .midnightBadge(size)
            .foregroundStyle(ink)
            .padding(.horizontal, size * 0.8)
            .padding(.vertical, size / 3)
            .background {
                if case .resume = state {
                    Rectangle().fill(MidnightGradients.field(colorScheme))
                }
            }
            .overlay {
                switch state {
                case .new: Rectangle().strokeBorder(isFocused ? MidnightPalette.selectedInk : MidnightPalette.accent, lineWidth: 1)
                case .watched: Rectangle().strokeBorder(isFocused ? MidnightPalette.selectedSub : MidnightPalette.line, lineWidth: 1)
                case .resume: EmptyView()
                }
            }
    }

    private var ink: Color {
        switch state {
        case .resume: MidnightPalette.fieldInk
        case .new: isFocused ? MidnightPalette.selectedInk : MidnightPalette.accentSoft
        case .watched: isFocused ? MidnightPalette.selectedSub : MidnightPalette.inkSoft
        }
    }
}
#endif
