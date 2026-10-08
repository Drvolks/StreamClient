//
//  MacChannelActionCell.swift
//  nextpvr-apple-client
//
//  One icon cell of a macOS card's action strip. Hovering fills it with the
//  accent field and inverts the icon. A dimmed cell stays clickable only when
//  `isEnabled`.
//

#if os(macOS)
import SwiftUI

struct MacChannelActionCell: View {
    let systemImage: String
    let help: String
    var isEnabled = true
    var isDimmed = false
    var hoverFill: Color?
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var isHot: Bool { isHovering && isEnabled }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isHot ? MidnightPalette.fieldInk : MidnightPalette.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if isHot {
                        if let hoverFill {
                            Rectangle().fill(hoverFill)
                        } else {
                            Rectangle().fill(MidnightGradients.field(colorScheme))
                        }
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isDimmed || !isEnabled ? 0.35 : 1)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
#endif
