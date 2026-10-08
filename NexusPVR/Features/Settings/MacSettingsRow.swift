//
//  MacSettingsRow.swift
//  nextpvr-apple-client
//
//  One row of a macOS Settings pane: label, optional sub-line, and a
//  trailing control.
//

#if os(macOS)
import SwiftUI

struct MacSettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Theme.spacingMD) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.archivo(15, .extraBold))
                    .tracking(-0.15)
                    .foregroundStyle(MidnightPalette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.archivo(11.5))
                        .foregroundStyle(MidnightPalette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.spacingMD)
            trailing
        }
        .padding(.vertical, 9)
        .frame(minHeight: 46)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MidnightPalette.lineSoft).frame(height: 1)
        }
    }
}

extension MacSettingsRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}
#endif
