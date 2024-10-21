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
        GeneralMacHeader(title: "email")
    }
    
    var view: some View {
        VStack {
            emailField
            emailMismatchLabel
            Spacer()
            buttons
        }
        .padding(.horizontal, 25)
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
        .autocorrectionDisabled()
        .borderlessTextFieldStyle()
    }
}
#endif
