//
//  MidnightSwitch.swift
//  nextpvr-apple-client
//
//  The track and knob drawn by `MidnightToggleStyle`.
//

#if !os(tvOS)
import SwiftUI

struct MidnightSwitch: View {
    let isOn: Bool
    let scheme: ColorScheme

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Group {
                if isOn {
                    Rectangle().fill(MidnightGradients.field(scheme))
                } else {
                    Rectangle().fill(MidnightPalette.barSoft)
                }
            }
            Text(isOn ? "ON" : "OFF")
                .font(.archivo(9, .extraBold))
                .foregroundStyle(isOn ? MidnightPalette.chipInk : MidnightPalette.fieldInk)
                .frame(width: 32)
                .frame(maxHeight: .infinity)
                .background(isOn ? MidnightPalette.chipBg : MidnightPalette.inkFaint)
        }
        .frame(width: 66, height: 26)
        .overlay {
            Rectangle().strokeBorder(isHovering ? MidnightPalette.accent : MidnightPalette.line, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}
#endif
