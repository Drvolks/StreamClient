//
//  TVKeyboardField.swift
//  nextpvr-apple-client
//
//  Opens the tvOS keyboard for a SwiftUI Button styled as a Midnight field,
//  so the field never shows the system's rounded focus platter. Put it, at
//  1×1 and hidden, in the button's background and set `requestFocus` when
//  the button is selected. Used by the Channels search and Settings > Topics.
//

#if os(tvOS)
import SwiftUI
import UIKit

struct TVKeyboardField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    @Binding var requestFocus: Bool
    var returnKeyType: UIReturnKeyType = .search
    var onFocusChange: (Bool) -> Void = { _ in }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: TVKeyboardField

        init(parent: TVKeyboardField) {
            self.parent = parent
        }

        @objc func textDidChange(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onFocusChange(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.onFocusChange(false)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = TVKeyboardTextField(frame: .zero)
        field.delegate = context.coordinator
        field.placeholder = placeholder
        field.text = text
        field.textColor = UIColor.white
        field.tintColor = UIColor.white
        field.borderStyle = .none
        field.returnKeyType = returnKeyType
        field.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text {
            uiView.text = text
        }
        uiView.placeholder = placeholder

        if requestFocus {
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            }
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }
}
#endif
