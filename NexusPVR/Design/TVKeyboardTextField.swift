//
//  TVKeyboardTextField.swift
//  nextpvr-apple-client
//
//  Zero-size `UITextField` that only ever drives the on-screen keyboard for
//  a TVKeyboardField. `canBecomeFocused` is `false` so the focus engine never
//  lands on it — the visible focusable element is the SwiftUI `Button` in
//  front of it.
//

#if os(tvOS)
import UIKit

final class TVKeyboardTextField: UITextField {
    override var canBecomeFocused: Bool { false }
}
#endif
