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

struct MaxLengthModifier: ViewModifier {
    @Binding var text: String
    var maxLength: Int = 108
    
    func body(content: Content) -> some View {
        content
            .onChange(of: text) { _, newValue in
                if newValue.count > maxLength {
                    text = String(newValue.prefix(maxLength))
                }
            }
    }
}

extension View {
    func maxLength(_ text: Binding<String>, _ maxLength: Int = 108) -> some View {
        self.modifier(MaxLengthModifier(text: text, maxLength: maxLength))
    }
}
