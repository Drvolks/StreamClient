//
//  TVDetailPanel.swift
//  nextpvr-apple-client
//
//  The panel of a tvOS details popup, centred over a dimmed page. Used
//  inside a clear full-screen cover (see `detailCover`).
//

#if os(tvOS)
import SwiftUI

struct TVDetailPanel<Content: View>: View {
    var width: CGFloat = 800
    var maxHeight: CGFloat = 860
    @ViewBuilder let content: Content

    private let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    var body: some View {
        ZStack {
            scrim
                .ignoresSafeArea()
            ground(
                content
                    .frame(width: width)
                    .frame(maxHeight: maxHeight)
                    .fixedSize(horizontal: false, vertical: true)
            )
        }
    }

    /// Lighter under glass, which needs the page behind it to show through.
    private var scrim: Color {
        if #available(tvOS 26, *) {
            Color.black.opacity(0.3)
        } else {
            Color.black.opacity(0.6)
        }
    }

    /// Liquid Glass on tvOS 26; Midnight's opaque plate with its accent rule
    /// before that.
    @ViewBuilder
    private func ground(_ panel: some View) -> some View {
        if #available(tvOS 26, *) {
            panel.glassEffect(.regular, in: shape)
        } else {
            panel
                .background(MidnightPalette.railHead)
                .overlay(alignment: .top) {
                    Rectangle().fill(MidnightPalette.accent).frame(height: 4)
                }
                .clipShape(shape)
                .overlay { shape.strokeBorder(MidnightPalette.line, lineWidth: 1) }
        }
    }
}
#endif
