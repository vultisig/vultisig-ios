//
//  FastVaultEmailView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI

extension FastVaultEmailView {
    var content: some View {
        ZStack {
            Background()
            main
        }
    }
    
    var main: some View {
        VStack {
            headerMac
            view
        }
        .navigationDestination(isPresented: $isLinkActive) {
            FastVaultSetPasswordView(tssType: tssType, vault: vault, selectedTab: selectedTab, fastVaultEmail: email, fastVaultExist: fastVaultExist)
        }
    }

    var headerMac: some View {
        GeneralMacHeader(title: "", showActions: !backButtonHidden)
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
        .padding(.horizontal, 25)
    }
    
    func textfield(title: String, text: Binding<String>) -> some View {
        HStack {
            TextField("", text: text, prompt: Text(NSLocalizedString(title, comment: ""))
                .foregroundColor(Color.neutral500)
                .font(theme.fonts.caption12)
            )
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .submitLabel(.done)
            .focused($isEmailFocused)
            .onSubmit {
                handleTap()
            }
            
            if !email.isEmpty {
                clearButton
            }
        }
        .padding(12)
        .background(Color.blue600)
        .cornerRadius(12)
        .autocorrectionDisabled()
        .borderlessTextFieldStyle()
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(getBorderColor(), lineWidth: 1)
        )
        .padding(.top, 32)
    }
}
#endif
