//
//  OTPCharTextField.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/07/2025.
//

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

        @objc func textFieldDidChange(_ textField: UITextField) {
            let newText = textField.text ?? ""
            if parent.text.isEmpty {
                parent.text = newText
                return
            }
            
            let filteredNewText = newText.filter { $0 != Character(parent.text) }
            textField.text = String(filteredNewText)
            parent.text = String(filteredNewText)
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
