//
//  MacSettingsIndexRow.swift
//  nextpvr-apple-client
//
//  One category in the macOS Settings index. Selected rows sit on the accent
//  field; hovered rows get a leading accent bar.
//

#if os(macOS)
import SwiftUI

struct MacSettingsIndexRow: View {
    let category: SettingsCategory
    let summary: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacingSM + 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.archivo(15, .extraBold))
                        .textCase(.uppercase)
                    Text(summary)
                        .font(.archivo(11.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .opacity(isSelected ? 0.9 : 1)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? MidnightPalette.fieldInk : MidnightPalette.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    Rectangle().fill(MidnightGradients.field(colorScheme))
                }
            }
            .overlay(alignment: .leading) {
                if isHovering && !isSelected {
                    Rectangle().fill(MidnightPalette.accent).frame(width: 5)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(MidnightPalette.lineSoft).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("settings-category-\(category.title.lowercased())")
    }
}
#endif
