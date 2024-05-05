//
//  TappableTextFieldStyle.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 15.04.2024.
//

import SwiftUI

struct TappableTextFieldStyle: TextFieldStyle {

    @FocusState private var textFieldFocused: Bool

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .focused($textFieldFocused)
            .onTapGesture {
                textFieldFocused = true
            }
    }
}
