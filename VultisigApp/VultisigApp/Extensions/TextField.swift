//
//  TextField.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 30/06/24.
//
// This file extension is used to limit the number of characters that can be entered in a TextField.

import Foundation
import SwiftUI
import Combine

#if canImport(UIKit)
import UIKit

private var maxLengthKey: UInt8 = 0

extension UITextField {
    @IBInspectable var maxLength: Int {
        get {
            return objc_getAssociatedObject(self, &maxLengthKey) as? Int ?? 50
        }
        set {
            objc_setAssociatedObject(self, &maxLengthKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            addTarget(self, action: #selector(checkMaxLength), for: .editingChanged)
        }
    }
    
    @objc func checkMaxLength() {
        guard let text = self.text, maxLength > 0 else { return }
        if text.count > maxLength {
            self.text = String(text.prefix(maxLength))
        }
    }
}
#endif

struct MaxLengthTextField: View {
    @Binding var text: String
    var maxLength: Int = 50
    
    var body: some View {
        TextField("", text: $text)
            .onChange(of: text) { newValue in
                if newValue.count > maxLength {
                    text = String(newValue.prefix(maxLength))
                }
            }
    }
}

struct MaxLengthModifier: ViewModifier {
    @Binding var text: String
    var maxLength: Int = 50
    
    func body(content: Content) -> some View {
        content
            .background(Color.clear) // Set background to clear to avoid interfering with the layout
            .overlay(MaxLengthTextField(text: $text, maxLength: maxLength).background(Color.clear)) // Ensure the inner TextField also has a clear background
    }
}

extension View {
    func maxLength(_ text: Binding<String>, _ maxLength: Int = 50) -> some View {
        self.modifier(MaxLengthModifier(text: text, maxLength: maxLength))
    }
}
