//
//  MidnightPicker.swift
//  nextpvr-apple-client
//
//  A boxless menu picker: the current value in uppercase accent ink over a
//  2pt accent underline. The menu lists the options with a checkmark on the
//  selected one.
//

#if os(macOS)
import SwiftUI

struct MidnightPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(label: String, value: Value)]

    @State private var isHovering = false

    var body: some View {
        Menu {
            // Plain buttons rather than an inline Picker: macOS draws inline
            // picker options as toggles, which an ancestor's ToggleStyle (the
            // Settings page's ON/OFF switch) would restyle.
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            Text(currentLabel)
                .font(.archivo(13, .extraBold))
                .textCase(.uppercase)
                .foregroundStyle(MidnightPalette.accentSoft)
                .lineLimit(1)
                .padding(.horizontal, Theme.spacingSM + 2)
                .padding(.vertical, 5)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(MidnightPalette.accent)
                        .frame(height: 2)
                }
                .background(isHovering ? MidnightPalette.hoverTint : .clear)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
        .accessibilityValue(currentLabel)
    }

    private var currentLabel: String {
        options.first(where: { $0.value == selection })?.label ?? "—"
    }
}
#endif
