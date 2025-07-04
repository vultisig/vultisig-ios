//
//  MemoTextField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-04.
//

import SwiftUI

struct MemoTextField: View {
    @Binding var memo: String
    
    @Environment(\.isEnabled) private var isEnabled
    
    var body: some View {
        container
            .font(.body16BrockmannMedium)
            .padding(16)
            .background(Color.blue600)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue400, lineWidth: 1)
            )
            .padding(1)
    }
    
    var content: some View {
        HStack(spacing: 0) {
            textField
            Spacer()
            pasteButton
        }
    }
    
    var textField: some View {
        TextField(NSLocalizedString("enterMemo", comment: "").capitalized, text: $memo)
            .borderlessTextFieldStyle()
            .submitLabel(.next)
            .disableAutocorrection(true)
            .textFieldStyle(TappableTextFieldStyle())
            .foregroundColor(isEnabled ? .neutral0 : .neutral300)
    }
    
    var pasteButton: some View {
        Button {
            pasteAddress()
        } label: {
            pasteLabel
        }
    }
    
    var pasteLabel: some View {
        Image(systemName: "square.on.square")
    }
}

#Preview {
    MemoTextField(memo: .constant(""))
}
