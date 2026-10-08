//
//  MidnightOutlineButtonStyle.swift
//  nextpvr-apple-client
//
//  Secondary action: a short verb in a 1pt rule box. Destructive actions
//  use the danger ink, the only place it appears.
//

#if os(macOS)
import SwiftUI

struct MidnightOutlineButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        MidnightOutlineButtonBody(configuration: configuration, isDestructive: isDestructive)
    }
}

private struct MidnightOutlineButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isDestructive: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.archivo(13, .extraBold))
            .foregroundStyle(isDestructive ? MidnightPalette.danger : MidnightPalette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(isHovering ? MidnightPalette.hoverTint : .clear)
            .overlay {
                Rectangle().strokeBorder(
                    configuration.isPressed ? MidnightPalette.accentSoft
                        : isHovering ? MidnightPalette.accent : MidnightPalette.line,
                    lineWidth: 1
                )
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { isHovering = $0 }
    }
}
#endif
