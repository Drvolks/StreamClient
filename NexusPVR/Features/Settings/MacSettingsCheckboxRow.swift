//
//  MacSettingsCheckboxRow.swift
//  nextpvr-apple-client
//
//  An indented, square checkbox row under a Guide sidebar toggle (one per
//  channel group or profile).
//

#if !os(tvOS)
import SwiftUI

struct MacSettingsCheckboxRow: View {
    let title: String
    let isChecked: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.spacingSM + 4) {
                ZStack {
                    if isChecked {
                        Rectangle().fill(MidnightGradients.field(colorScheme))
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(MidnightPalette.fieldInk)
                    } else {
                        Rectangle().fill(MidnightPalette.inputBg)
                    }
                }
                .frame(width: 22, height: 22)
                .overlay {
                    Rectangle().strokeBorder(isHovering ? MidnightPalette.accent : MidnightPalette.line, lineWidth: 1)
                }

                Text(title)
                    .font(.archivo(13.5, .semibold))
                    .foregroundStyle(MidnightPalette.ink)
                Spacer()
            }
            .padding(.leading, 22)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }
}
#endif
