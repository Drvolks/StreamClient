//
//  MidnightNavigationTitle.swift
//  nextpvr-apple-client
//
//  The iOS navigation bar title (Midnight): a kicker (section and readout,
//  in the accent) over the page title in the display face, leading-aligned
//  next to the menu button. The plain title is still set for accessibility
//  and the back button.
//

#if os(iOS)
import SwiftUI

struct MidnightNavigationTitle: ViewModifier {
    let title: String
    var kicker: String?

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let kicker {
                            Text(kicker)
                                .midnightKicker(9)
                                .foregroundStyle(MidnightPalette.accent)
                                .lineLimit(1)
                        }
                        Text(title)
                            .midnightDisplay(kicker == nil ? 22 : 19)
                            .foregroundStyle(MidnightPalette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
            }
            .toolbarBackground(MidnightPalette.railHead, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    /// `kicker` is the small accent line above the title, e.g.
    /// "Recordings · 4 recordings".
    func midnightNavigationTitle(_ title: String, kicker: String? = nil) -> some View {
        modifier(MidnightNavigationTitle(title: title, kicker: kicker))
    }
}
#endif
