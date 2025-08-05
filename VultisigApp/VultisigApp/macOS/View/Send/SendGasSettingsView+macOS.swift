//
//  SendGasSettingsView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(macOS)
import SwiftUI

extension SendGasSettingsView {
    var content: some View {
        ZStack {
            Background()
                .frame(width: 500)
            
            VStack {
                headerMac
                view
                buttons
            }
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
                    .colorScheme(.dark)
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
                .foregroundColor(.blue600)
        )
        .padding(.horizontal, 16)
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "Advanced")
    }
    
    var buttons: some View {
        VStack(spacing: 20) {
            continueButton
        }
        .padding(40)
    }
    
    var continueButton: some View {
        PrimaryButton(title: "save") {
            save()
            presentationMode.wrappedValue.dismiss()
        }
        .buttonStyle(.plain)
    }
}
#endif
