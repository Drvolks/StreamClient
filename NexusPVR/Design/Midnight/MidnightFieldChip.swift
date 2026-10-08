//
//  MidnightFieldChip.swift
//  nextpvr-apple-client
//
//  A status chip on the accent field ("CONNECTED", "LIVE NOW").
//

import SwiftUI

struct MidnightFieldChip: View {
    let text: String
    var size: CGFloat = 12

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.archivo(size, .extraBold))
            .tracking(0.06 * size)
            .textCase(.uppercase)
            .foregroundStyle(MidnightPalette.fieldInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(MidnightGradients.field(colorScheme))
    }
}
