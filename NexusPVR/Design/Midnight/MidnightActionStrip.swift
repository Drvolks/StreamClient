//
//  MidnightActionStrip.swift
//  nextpvr-apple-client
//
//  The row actions on iOS (recordings, topics): square icon cells in one
//  rounded strip, a hairline between them.
//

#if os(iOS)
import SwiftUI

struct MidnightActionStrip<Content: View>: View {
    @ViewBuilder let content: Content

    /// Side of one cell: the strip's height, and each cell's width.
    static var cellSide: CGFloat { 40 }

    private let shape = RoundedRectangle(cornerRadius: Theme.stripRadius, style: .continuous)

    var body: some View {
        HStack(spacing: 0) {
            Group(subviews: content) { cells in
                ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                    if index > 0 {
                        Rectangle().fill(MidnightPalette.lineSoft).frame(width: 1)
                    }
                    cell.frame(width: Self.cellSide)
                }
            }
        }
        .frame(height: Self.cellSide)
        .clipShape(shape)
        .overlay { shape.strokeBorder(MidnightPalette.line, lineWidth: 1) }
    }
}
#endif
