//
//  CommonTextEditor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/09/2025.
//

import SwiftUI

struct CommonTextEditor: View {
    @Binding var value: String
    let placeholder: String
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack {
                TextEditor(text: $value)
                    .textEditorStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(Theme.colors.textExtraLight)
                    .font(Theme.fonts.bodyMMedium)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .focused(isFocused)
                    .onSubmit {
                        onSubmit()
                    }
                
                if !value.isEmpty {
                    VStack {
                        clearButton
                        Spacer()
                    }
                }
            }
            if value.isEmpty {
                Text(placeholder)
                    .foregroundColor(Theme.colors.textExtraLight)
                    .font(Theme.fonts.bodyMMedium)
                    .padding(.leading, 6)
                    .padding(.top, isMacOS ? 0 : 8)
            }
        }
        .frame(height: 120)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.colors.bgSecondary)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }
    
    
    var clearButton: some View {
        Button {
            value = ""
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(Theme.colors.textExtraLight)
        }
    }
}
