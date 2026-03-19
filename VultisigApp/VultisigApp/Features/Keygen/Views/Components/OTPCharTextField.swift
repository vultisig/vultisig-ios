//
//  OTPCharTextField.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/07/2025.
//

#if os(iOS)
import SwiftUI
import UIKit

struct OTPCharTextField: UIViewRepresentable {
    @Binding var text: String
    var onDeleteWhenEmpty: () -> Void

    class OTPTextField: UITextField {
        var onDeleteWhenEmpty: (() -> Void)?

        override func deleteBackward() {
            if text?.isEmpty ?? true {
                onDeleteWhenEmpty?()
            }
            super.deleteBackward()
        }
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: OTPCharTextField

        init(parent: OTPCharTextField) {
            self.parent = parent
        }
        // swiftlint:disable:next unused_parameter
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            // Handle backspace
            if string.isEmpty {
                return true
            }

            // Only allow digits
            guard string.allSatisfy({ $0.isNumber }) else {
                return false
            }

            // If field is empty, allow the digit
            if textField.text?.isEmpty ?? true {
                return string.count == 1
            }

            // If field has text, replace it with the new digit
            textField.text = string
            parent.text = string
            return false // We handled the replacement ourselves
        }

        @objc func textFieldDidChange(_ textField: UITextField) {
            let newText = textField.text ?? ""
            parent.text = newText
        }
    }

    func makeUIView(context: Context) -> OTPTextField {
        let textField = OTPTextField()
        textField.textAlignment = .center
        textField.keyboardType = .numberPad
        textField.delegate = context.coordinator
        textField.autocorrectionType = .no
        textField.onDeleteWhenEmpty = onDeleteWhenEmpty
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textFieldDidChange(_:)), for: .editingChanged)
        return textField
    }
    // swiftlint:disable:next unused_parameter
    func updateUIView(_ uiView: OTPTextField, context: Context) {
        uiView.onDeleteWhenEmpty = onDeleteWhenEmpty
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
}
#endif
