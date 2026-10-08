//
//  MacSettingsIndexView.swift
//  nextpvr-apple-client
//
//  The middle column of macOS Settings: the eight numbered categories, each
//  with a live one-line summary of its current values.
//

#if os(macOS)
import SwiftUI

struct MacSettingsIndexView: View {
    @Binding var selection: SettingsCategory
    let summary: (SettingsCategory) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .midnightDisplay(28)
                    .foregroundStyle(MidnightPalette.ink)
                Text("Eight categories")
                    .midnightKicker(10.5)
                    .foregroundStyle(MidnightPalette.accent)
            }
            .padding(EdgeInsets(top: 18, leading: 18, bottom: 14, trailing: 18))
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle().fill(MidnightPalette.line).frame(height: 1)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(SettingsCategory.allCases) { category in
                        MacSettingsIndexRow(
                            category: category,
                            summary: summary(category),
                            isSelected: category == selection
                        ) {
                            selection = category
                        }
                    }
                }
            }
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MidnightPalette.railHead)
        .overlay(alignment: .trailing) {
            Rectangle().fill(MidnightPalette.line).frame(width: 1)
        }
    }
}
#endif
