//
//  MidnightFloatingGlass.swift
//  nextpvr-apple-client
//
//  Ground for chrome that floats over content (the search pill and its
//  dropdown): Liquid Glass where the system has it, a material and a shadow
//  before that.
//

import SwiftUI

extension View {
    /// `interactive` is for grounds the user touches directly.
    @ViewBuilder
    func midnightFloatingGlass(in shape: some Shape, interactive: Bool = false) -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
        }
    }
}
