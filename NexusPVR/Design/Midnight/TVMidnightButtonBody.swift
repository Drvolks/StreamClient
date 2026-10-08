//
//  TVMidnightButtonBody.swift
//  nextpvr-apple-client
//
//  The focus lift and shadow of TVMidnightButtonStyle.
//

#if os(tvOS)
import SwiftUI

struct TVMidnightButtonBody<Content: View>: View {
    let focusScale: CGFloat
    let isPressed: Bool
    @ViewBuilder let content: Content

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        content
            .shadow(color: isFocused ? .black.opacity(0.35) : .clear, radius: 12, x: 0, y: 5)
            .scaleEffect(isPressed ? 0.99 : (isFocused ? focusScale : 1.0))
            .animation(.easeInOut(duration: 0.14), value: isFocused)
            .animation(.easeInOut(duration: 0.08), value: isPressed)
    }
}
#endif
