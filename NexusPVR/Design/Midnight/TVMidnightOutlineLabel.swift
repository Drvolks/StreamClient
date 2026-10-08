//
//  TVMidnightOutlineLabel.swift
//  nextpvr-apple-client
//
//  A tvOS header button's face (Midnight): outlined at rest, inverted when
//  focused, as the guide's header fields are. Use inside a Button styled
//  with TVMidnightButtonStyle.
//

#if os(tvOS)
import SwiftUI

struct TVMidnightOutlineLabel: View {
    let title: String
    var systemImage: String?
    var isDestructive = false
    var isBusy = false

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 8) {
            if isBusy {
                ProgressView()
            } else if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .font(.archivo(Theme.scaledFont(17), .extraBold))
        .textCase(.uppercase)
        .foregroundStyle(ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(isFocused ? (isDestructive ? MidnightPalette.danger : MidnightPalette.selectedBg) : Color.clear)
        .overlay {
            Rectangle().strokeBorder(
                isFocused ? Color.clear : (isDestructive ? MidnightPalette.danger : MidnightPalette.line),
                lineWidth: 1
            )
        }
    }

    private var ink: Color {
        if isFocused { return isDestructive ? .white : MidnightPalette.selectedInk }
        return isDestructive ? MidnightPalette.danger : MidnightPalette.ink
    }
}
#endif
