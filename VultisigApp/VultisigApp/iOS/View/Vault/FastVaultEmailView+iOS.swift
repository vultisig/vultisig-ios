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
        .navigationTitle(NSLocalizedString("email", comment: ""))
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
            emailMismatchLabel
            Spacer()
            buttons
        }
    }
    
    func textfield(title: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(NSLocalizedString(title, comment: ""))
            .foregroundColor(Color.neutral500)
            .font(.body12Menlo)
        )
        .font(.body16Menlo)
        .foregroundColor(.neutral0)
        .submitLabel(.done)
        .padding(12)
        .background(Color.blue600)
        .cornerRadius(12)
        .textInputAutocapitalization(.never)
        .keyboardType(.emailAddress)
        .autocorrectionDisabled()
        .borderlessTextFieldStyle()
    }
}
#endif
