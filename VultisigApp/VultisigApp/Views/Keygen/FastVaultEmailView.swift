//
//  FastVaultEmailView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 11.09.2024.
//

import SwiftUI

struct FastVaultEmailView: View {
    let tssType: TssType
    let vault: Vault
    let selectedTab: SetupVaultState

    var fastVaultExist: Bool = false

    @State var email: String = ""
    @State var isLinkActive = false
    
    @State var isEmptyEmail: Bool = false
    @State var isInvalidEmail: Bool = false

    var body: some View {
        content
    }

    var emailField: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("enterYourEmail", comment: ""))
                .font(.body34BrockmannMedium)
                .foregroundColor(.neutral0)
                .padding(.top, 16)
            
            Text(NSLocalizedString("enterYourEmailDescription", comment: ""))
                .font(.body14BrockmannMedium)
                .foregroundColor(.extraLightGray)
            
            textfield(title: NSLocalizedString("email", comment: ""), text: $email)
        }
        .padding(.horizontal, 16)
    }

    var emptyEmailLabel: some View {
        HStack {
            Text(NSLocalizedString("emptyEmailPleaseCheck", comment: ""))
                .foregroundColor(.alertRed)
                .font(.body14Montserrat)
                .frame(height: 40)
            Spacer()
        }
        .padding(.horizontal, 16)
    }
    
    var validEmailLabel: some View {
        HStack {
            Text(NSLocalizedString("invalidEmailPleaseCheck", comment: ""))
                .foregroundColor(.alertRed)
                .font(.body14Montserrat)
                .frame(height: 40)
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    var button: some View {
        continueButton
            .padding(.top, 16)
            .padding(.bottom, 40)
            .padding(.horizontal, 16)
    }

    var continueButton: some View {
        Button(action: {
            handleTap()
        }) {
            FilledButton(title: "next")
        }
    }
    
    var clearButton: some View {
        Button {
            email = ""
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.neutral500)
        }
    }
    
    private func handleTap() {
        guard isEmptyEmailCheck() else {
            isEmptyEmail = true
            return
        }
        
        isEmptyEmail = false
        guard isValidEmailCheck() else {
            isInvalidEmail = true
            return
        }
        
        isInvalidEmail = false
        isLinkActive = true
    }
    
    private func isEmptyEmailCheck() -> Bool {
        return !email.isEmpty
    }

    private func isValidEmailCheck() -> Bool {
        return !email.trimmingCharacters(in: .whitespaces).isEmpty &&
               !email.isEmpty &&
                email.isValidEmail
    }
    
    func getBorderColor() -> Color {
        if isEmptyEmail || isInvalidEmail {
            return .alertRed
        } else {
            return .blue200
        }
    }
}
