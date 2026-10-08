//
//  MacSettingsPaneView.swift
//  nextpvr-apple-client
//
//  The right-hand pane of macOS Settings: a field header naming the
//  category, its rows, and one hint.
//

#if os(macOS)
import SwiftUI

struct MacSettingsPaneView<Content: View>: View {
    let category: SettingsCategory
    let hint: String
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(category.title)
                .midnightDisplay(38)
            .foregroundStyle(MidnightPalette.fieldInk)
            .padding(.horizontal, 30)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MidnightGradients.field(colorScheme))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                    MacSettingsHint(text: hint)
                        .padding(.top, Theme.spacingLG - 4)
                }
                .padding(.horizontal, 30)
                .padding(.top, Theme.spacingSM)
                .padding(.bottom, Theme.spacingXL)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MidnightGradients.ground(colorScheme))
    }
}
#endif
