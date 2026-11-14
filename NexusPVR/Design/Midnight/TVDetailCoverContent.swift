//
//  TVDetailCoverContent.swift
//  nextpvr-apple-client
//
//  A tvOS detail page, registered with TVDetailCoverGate while on screen.
//

#if os(tvOS)
import SwiftUI

/// Wraps a detail cover's content so `TVDetailCoverGate` knows it is on
/// screen. Keyed by an id per cover, so repeated appear/disappear calls
/// (e.g. from navigation inside the page) can't unbalance the gate.
struct TVDetailCoverContent<Content: View>: View {
    @State private var id = UUID()
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .onAppear { TVDetailCoverGate.shared.coverAppeared(id) }
            .onDisappear { TVDetailCoverGate.shared.coverDisappeared(id) }
    }
}
#endif
