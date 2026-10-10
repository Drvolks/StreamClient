//
//  ClickLocationRecorder.swift
//  nextpvr-apple-client
//
//  Remembers where the window was last clicked, so a popover can open next
//  to the click that asked for it (see `programDetailPopover`): the macOS
//  counterpart of `TouchLocationRecorder`. The monitor only watches
//  mouse-downs; it never swallows one.
//

#if os(macOS)
import AppKit

@MainActor
enum ClickLocationRecorder {
    /// The last mouse-down, in window (SwiftUI `.global`) coordinates.
    static var lastLocation: CGPoint?
    /// Height of the window that click landed in.
    static var lastWindowHeight: CGFloat?

    private static var monitor: Any?

    /// Starts watching, once; later calls do nothing.
    static func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            if let contentView = event.window?.contentView {
                // AppKit counts up from the bottom, SwiftUI down from the top.
                let height = contentView.bounds.height
                lastLocation = CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)
                lastWindowHeight = height
            }
            return event
        }
    }
}
#endif
