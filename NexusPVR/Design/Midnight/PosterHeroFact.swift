//
//  PosterHeroFact.swift
//  nextpvr-apple-client
//
//  One figure in a PosterHero: a large value over a small label
//  ("12" over "Recorded", "2019" over "Year").
//

import SwiftUI

struct PosterHeroFact: View {
    let label: String
    let value: String
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.archivo(30 * scale, .extraBold))
                .foregroundStyle(MidnightPalette.ink)
                .lineLimit(1)
            Text(label)
                .midnightKicker(9 * scale)
                .foregroundStyle(MidnightPalette.inkSoft)
        }
        .accessibilityElement(children: .combine)
    }
}
