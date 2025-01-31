//
//  FastVaultEmailView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(iOS)
import SwiftUI

extension FastVaultEmailView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationTitle(NSLocalizedString("", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    var main: some View {
        view
            .navigationDestination(isPresented: $isLinkActive) {
                FastVaultSetPasswordView(tssType: tssType, vault: vault, selectedTab: selectedTab, fastVaultEmail: email, fastVaultExist: fastVaultExist)
            }
    }
    
    var view: some View {
        VStack {
            emailField
            
            if isEmptyEmail {
                emptyEmailLabel
            } else if isInvalidEmail {
                validEmailLabel
            }
            
            Spacer()
            button
        }
    }
    
    func textfield(title: String, text: Binding<String>) -> some View {
        HStack {
            TextField("", text: text, prompt: Text(NSLocalizedString(title, comment: ""))
                .foregroundColor(Color.neutral500)
                .font(.body16BrockmannMedium)
            )
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .submitLabel(.done)
            
            if !email.isEmpty {
                clearButton
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(getBorderColor(), lineWidth: 1)
        )
        .textInputAutocapitalization(.never)
        .keyboardType(.emailAddress)
        .autocorrectionDisabled()
        .borderlessTextFieldStyle()
        .padding(.top, 32)
    }
}
#endif
