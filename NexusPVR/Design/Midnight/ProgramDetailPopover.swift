//
//  ProgramDetailPopover.swift
//  nextpvr-apple-client
//
//  Presents a program's details. On iOS they open as a popover next to the
//  tap that asked for them, on iPhone as on iPad, rather than as a sheet
//  from the bottom of the screen; tvOS and macOS present them as before
//  (see `detailCover`).
//

import SwiftUI

extension View {
    func programDetailPopover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(iOS)
        modifier(TapAnchoredPopover(item: item, onDismiss: onDismiss, popoverContent: content))
        #else
        detailCover(item: item, onDismiss: onDismiss, content: content)
        #endif
    }
}

#if os(iOS)
private struct TapAnchoredPopover<Item: Identifiable, PopoverContent: View>: ViewModifier {
    @Binding var item: Item?
    let onDismiss: (() -> Void)?
    @ViewBuilder let popoverContent: (Item) -> PopoverContent

    /// What the popover shows. Set one step after `item`, once the tap that
    /// asked for it has been read into `anchor`.
    @State private var presented: Item?
    @State private var anchor = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var frameInWindow = CGRect.zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .global)
            } action: { frame in
                frameInWindow = frame
            }
            .onChange(of: item?.id) {
                guard let item else {
                    presented = nil
                    return
                }
                anchor = anchorRect()
                presented = item
            }
            .popover(item: $presented, attachmentAnchor: .rect(.rect(anchor))) { value in
                popoverContent(value)
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(MidnightPalette.railHead)
            }
            .onChange(of: presented?.id) {
                // Dismissed by tapping outside: clear the caller's item too.
                if presented == nil, item != nil {
                    item = nil
                    onDismiss?()
                }
            }
    }

    /// A small rect at the last tap, in this view's coordinates; the middle
    /// of the view when no tap is known.
    private func anchorRect() -> CGRect {
        guard let tap = TouchLocationRecorder.lastLocation, frameInWindow != .zero else {
            return CGRect(x: frameInWindow.width / 2, y: frameInWindow.height / 2, width: 1, height: 1)
        }
        return CGRect(x: tap.x - frameInWindow.minX - 1, y: tap.y - frameInWindow.minY - 1, width: 2, height: 2)
    }
}
#endif
