//
//  DetailCoverModifier.swift
//  nextpvr-apple-client
//
//  Presents a program or recording's details: a sheet on iOS and macOS, a
//  full-screen cover on tvOS. The tvOS system sheet draws its own rounded
//  panel, whose rim showed as a line above and below the details; the cover
//  is clear, so the details draw their own square panel (TVDetailPanel).
//

import SwiftUI

extension View {
    func detailCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(tvOS)
        fullScreenCover(item: item, onDismiss: onDismiss) { value in
            content(value)
                .presentationBackground(.clear)
        }
        #else
        sheet(item: item, onDismiss: onDismiss, content: content)
        #endif
    }
}
