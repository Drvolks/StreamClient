//
//  MidnightControlShape.swift
//  nextpvr-apple-client
//
//  Outline of buttons and input fields: a capsule, to sit with the
//  system's own controls.
//

import SwiftUI

struct MidnightControlShape: InsettableShape {
    var inset: CGFloat = 0

    nonisolated func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2, style: .continuous)
    }

    nonisolated func inset(by amount: CGFloat) -> MidnightControlShape {
        MidnightControlShape(inset: inset + amount)
    }
}
