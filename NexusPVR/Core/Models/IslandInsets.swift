//
//  IslandInsets.swift
//  nextpvr-apple-client
//
//  Horizontal insets that keep content clear of the Dynamic Island (#176)
//
//  A landscape iPhone reports the same safe-area inset on both sides, though
//  only one of them has the island in it. Full-bleed layouts (the guide grid,
//  the menu) inset the island's side and run to the edge of the other; which
//  side that is depends on which way the phone was turned.
//

import Foundation
#if os(iOS)
import UIKit
#endif

nonisolated struct IslandInsets: Equatable, Sendable {
    var left: CGFloat = 0
    var right: CGFloat = 0

    /// On a landscape iPhone, the safe-area inset of the island's side only.
    /// Everywhere else (portrait, iPad) the window's own insets, untouched.
    static func resolve(isPhone: Bool, islandSide: IslandSide, safeLeft: CGFloat, safeRight: CGFloat) -> IslandInsets {
        guard isPhone else { return IslandInsets(left: safeLeft, right: safeRight) }
        switch islandSide {
        case .left: return IslandInsets(left: safeLeft, right: 0)
        case .right: return IslandInsets(left: 0, right: safeRight)
        case .none: return IslandInsets(left: safeLeft, right: safeRight)
        }
    }
}

#if os(iOS)
extension IslandInsets {
    /// The insets for the key window as it is laid out right now.
    @MainActor static var current: IslandInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return IslandInsets() }
        let orientation = window.windowScene?.effectiveGeometry.interfaceOrientation ?? .unknown
        return resolve(
            isPhone: UIDevice.current.userInterfaceIdiom == .phone,
            islandSide: IslandSide(orientation),
            safeLeft: window.safeAreaInsets.left,
            safeRight: window.safeAreaInsets.right
        )
    }
}
#endif
