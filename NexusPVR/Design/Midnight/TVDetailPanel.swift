//
//  TVDetailPanel.swift
//  nextpvr-apple-client
//
//  The square Midnight panel of a tvOS details popup, centred over a dimmed
//  page. Used inside a clear full-screen cover (see `detailCover`).
//

#if os(tvOS)
import SwiftUI

struct TVDetailPanel<Content: View>: View {
    var width: CGFloat = 800
    var maxHeight: CGFloat = 860
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            content
                .frame(width: width)
                .frame(maxHeight: maxHeight)
                .fixedSize(horizontal: false, vertical: true)
                .background(MidnightPalette.railHead)
                .overlay { Rectangle().strokeBorder(MidnightPalette.line, lineWidth: 1) }
                .overlay(alignment: .top) {
                    Rectangle().fill(MidnightPalette.accent).frame(height: 4)
                }
        }
    }
}
#endif
