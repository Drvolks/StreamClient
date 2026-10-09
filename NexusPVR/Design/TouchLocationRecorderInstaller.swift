//
//  TouchLocationRecorderInstaller.swift
//  nextpvr-apple-client
//
//  Adds a TouchLocationRecorder to the window the app's root view is in.
//  Put it in the root view's background.
//

#if os(iOS)
import SwiftUI
import UIKit

struct TouchLocationRecorderInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { InstallerView() }
    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class InstallerView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window,
                  !(window.gestureRecognizers ?? []).contains(where: { $0 is TouchLocationRecorder }) else { return }
            window.addGestureRecognizer(TouchLocationRecorder(target: nil, action: nil))
        }
    }
}
#endif
