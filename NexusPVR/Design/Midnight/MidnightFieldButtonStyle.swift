//
//  MidnightFieldButtonStyle.swift
//  nextpvr-apple-client
//
//  Primary action: a short verb on the accent field.
//

#if !os(tvOS)
import SwiftUI

struct MidnightFieldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MidnightFieldButtonBody(configuration: configuration)
    }
}

private struct MidnightFieldButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.archivo(13, .extraBold))
            .foregroundStyle(MidnightPalette.fieldInk)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(MidnightGradients.field(colorScheme), in: MidnightControlShape())
            .overlay {
                if isHovering {
                    MidnightControlShape().strokeBorder(MidnightPalette.accentSoft, lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.82 : isEnabled ? 1 : 0.45)
            .contentShape(MidnightControlShape())
            .onHover { isHovering = $0 }
    }
}
#endif
