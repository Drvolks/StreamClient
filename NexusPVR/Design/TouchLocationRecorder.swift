//
//  TouchLocationRecorder.swift
//  nextpvr-apple-client
//
//  Remembers where the screen was last touched, so a popover can open next
//  to the tap that asked for it (see `programDetailPopover`). A gesture
//  recognizer on the window notes each touch-down and fails at once: it
//  never claims a touch, so buttons and scrolling are unaffected.
//

#if os(iOS)
import UIKit

final class TouchLocationRecorder: UIGestureRecognizer {
    /// The last touch-down, in window (SwiftUI `.global`) coordinates.
    @MainActor static var lastLocation: CGPoint?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first {
            Self.lastLocation = touch.location(in: nil)
        }
        state = .failed
    }
}
#endif
