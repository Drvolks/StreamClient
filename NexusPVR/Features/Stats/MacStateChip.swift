//
//  MacStateChip.swift
//  nextpvr-apple-client
//
//  A server-reported state ("streaming", "success", "error", …) as a
//  Midnight chip: live states on the accent field, errors in the danger
//  colour, anything else outlined.
//

#if os(macOS) && DISPATCHERPVR
import SwiftUI

struct MacStateChip: View {
    let state: String

    @Environment(\.colorScheme) private var colorScheme

    private var label: String {
        state.replacingOccurrences(of: "_", with: " ")
    }

    var body: some View {
        switch state {
        case "streaming", "active":
            Text(label)
                .badgeLabel()
                .foregroundStyle(MidnightPalette.fieldInk)
                .background { Rectangle().fill(MidnightGradients.field(colorScheme)) }
        case "error":
            Text(label)
                .badgeLabel()
                .foregroundStyle(MidnightPalette.danger)
                .overlay { Rectangle().strokeBorder(MidnightPalette.danger, lineWidth: 1) }
        default:
            Text(label)
                .badgeLabel()
                .foregroundStyle(MidnightPalette.inkSoft)
                .overlay { Rectangle().strokeBorder(MidnightPalette.line, lineWidth: 1) }
        }
    }
}
#endif
