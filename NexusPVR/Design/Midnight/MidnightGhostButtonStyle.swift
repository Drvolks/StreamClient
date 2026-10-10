//
//  MidnightGhostButtonStyle.swift
//  nextpvr-apple-client
//
//  Tertiary action: accent text with no box, tinted on hover.
//

#if !os(tvOS)
import SwiftUI

struct MidnightGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MidnightGhostButtonBody(configuration: configuration)
    }
}

private struct MidnightGhostButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.archivo(12.5, .extraBold))
            .foregroundStyle(MidnightPalette.accentSoft)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isHovering ? MidnightPalette.hoverTint : .clear, in: MidnightControlShape())
            .opacity(configuration.isPressed ? 0.82 : isEnabled ? 1 : 0.45)
            .contentShape(MidnightControlShape())
            .onHover { isHovering = $0 }
    }
}
#endif
