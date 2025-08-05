//
//  SendGasSettingsView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(iOS)
import SwiftUI

extension SendGasSettingsView {
    var content: some View {
        NavigationView {
            ZStack {
                Background()
                view
            }
            .navigationTitle("Advanced")
            .navigationBarItems(leading: backButton, trailing: saveButton)
            .navigationBarTitleTextColor(Theme.colors.textPrimary)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    func textField(title: String, text: Binding<String>, label: String? = nil, disabled: Bool = false) -> some View {
        VStack {
            HStack {
                TextField("", text: text, prompt: Text(title).foregroundColor(Theme.colors.textLight))
                    .borderlessTextFieldStyle()
                    .foregroundColor(disabled ? Theme.colors.textLight : Theme.colors.textPrimary)
                    .tint(Theme.colors.textPrimary)
                    .font(Theme.fonts.bodyMRegular)
                    .submitLabel(.next)
                    .disableAutocorrection(true)
                    .textFieldStyle(TappableTextFieldStyle())
                    .textInputAutocapitalization(.never)
                    .keyboardType(.decimalPad)
                    .textContentType(.oneTimeCode)
                    .disabled(disabled)

                if let label {
                    Text(label)
                        .foregroundColor(Theme.colors.textLight)
                        .font(Theme.fonts.bodyMRegular)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
        }
        .background(
            RoundedRectangle(cornerSize: .init(width: 5, height: 5))
                .foregroundColor(Theme.colors.bgSecondary)
        )
        .padding(.horizontal, 16)
    }
}
#endif
