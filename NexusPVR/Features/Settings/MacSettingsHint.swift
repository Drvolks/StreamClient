//
//  MacSettingsHint.swift
//  nextpvr-apple-client
//
//  The single explanatory note at the foot of a macOS Settings pane.
//

#if os(macOS)
import SwiftUI

struct MacSettingsHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.archivo(12.5))
            .lineSpacing(3)
            .foregroundStyle(MidnightPalette.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 12)
            .padding(.leading, 20)
            .padding(.trailing, 16)
            .frame(maxWidth: 470, alignment: .leading)
            .background(MidnightPalette.barSoft)
            .overlay(alignment: .leading) {
                Rectangle().fill(MidnightPalette.accent).frame(width: 6)
            }
    }
}
#endif
