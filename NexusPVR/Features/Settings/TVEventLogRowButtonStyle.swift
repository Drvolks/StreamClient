//
//  TVEventLogRowButtonStyle.swift
//  PVR Client
//
//  Focusable Event Log rows on tvOS.
//

#if os(tvOS)
import SwiftUI

/// Event Log rows and log blocks on tvOS. Rows have to be focusable: the
/// Siri Remote only scrolls a list by moving focus through it.
struct TVEventLogRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TVEventLogRowBody(isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

private struct TVEventLogRowBody<Label: View>: View {
    @Environment(\.isFocused) private var isFocused
    let isPressed: Bool
    @ViewBuilder let label: Label

    var body: some View {
        label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.spacingMD)
            .padding(.vertical, Theme.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSM)
                    .fill(isFocused ? Theme.surfaceHighlight : Theme.surface.opacity(0.35))
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSM)
                    .stroke(isFocused ? Theme.accent : Color.clear, lineWidth: 2)
            }
            .scaleEffect(isPressed ? 0.99 : isFocused ? 1.01 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isFocused)
            .animation(.easeInOut(duration: 0.12), value: isPressed)
    }
}
#endif
