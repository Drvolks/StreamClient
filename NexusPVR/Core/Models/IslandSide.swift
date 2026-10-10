//
//  IslandSide.swift
//  nextpvr-apple-client
//
//  Which side of a landscape iPhone the Dynamic Island (or notch) is on (#176)
//

import Foundation
#if os(iOS)
import UIKit
#endif

nonisolated enum IslandSide: Sendable {
    /// Portrait, or a device with nothing cut into its long edges.
    case none
    case left
    case right
}

#if os(iOS)
extension IslandSide {
    /// `.landscapeRight` is the interface with the home indicator's edge on
    /// the right, so the top of the phone — and the island — is on the left.
    init(_ orientation: UIInterfaceOrientation) {
        switch orientation {
        case .landscapeRight: self = .left
        case .landscapeLeft: self = .right
        default: self = .none
        }
    }
}
#endif
