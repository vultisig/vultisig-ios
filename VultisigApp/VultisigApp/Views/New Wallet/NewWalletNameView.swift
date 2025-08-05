//
//  NewWalletNameView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-12.
//

import SwiftUI
import SwiftData

struct NewWalletNameView: View {
    let tssType: TssType
    let selectedTab: SetupVaultState

    @State var name: String
    @State var isLinkActive = false
    @FocusState private var isNameFocused: Bool
    @State var errorMessage: String = ""
    
    @Query var vaults: [Vault]
    
    var body: some View {
        content
    }
    
    var view: some View {
        VStack {
            fields
            if !errorMessage.isEmpty {
                error
            }
            Spacer()
            button
        }
        .onAppear() {
            isNameFocused = true
        }
    }
    var error: some View {
        Text(NSLocalizedString(errorMessage, comment: ""))
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(.alertRed)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
    }
    var textfield: some View {
        HStack {
            TextField(NSLocalizedString("enterVaultName", comment: "").capitalized, text: $name)
                .font(Theme.fonts.bodyMMedium)
                .foregroundColor(.neutral0)
                .submitLabel(.done)
                .focused($isNameFocused)
                .onSubmit {
                    verifyVault()
                }
                .maxLength($name, 64)
            
            if !name.isEmpty {
                clearButton
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(12)
        .colorScheme(.dark)
        .borderlessTextFieldStyle()
        .autocorrectionDisabled()
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(errorMessage.isEmpty ? Color.blue200 : Color.alertRed, lineWidth: 1)
        )
        .padding(.top, 32)
    }
    
    var clearButton: some View {
        Button {
            resetPlaceholderName()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.neutral500)
        }
    }
    
    var button: some View {
        PrimaryButton(title: "next") {
            verifyVault()
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .navigationDestination(isPresented: $isLinkActive) {
            if selectedTab.isFastVault {
                FastVaultEmailView(tssType: tssType, vault: Vault(name: name), selectedTab: selectedTab)
            } else {
                PeerDiscoveryView(tssType: tssType, vault: Vault(name: name), selectedTab: selectedTab, fastSignConfig: nil)
            }
        }
    }
    
    var fields: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("nameYourVault", comment: ""))
                .font(Theme.fonts.largeTitle)
                .foregroundColor(.neutral0)
                .padding(.top, 16)
            
            Text(NSLocalizedString("newWalletNameDescription", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(.extraLightGray)
            
            textfield
        }
        .padding(.horizontal, 16)
    }

    private func verifyVault() {
        if name.isEmpty {
            errorMessage = NSLocalizedString("enterVaultName", comment: "")
            return
        }
        
        for vault in vaults {
            if vault.name.caseInsensitiveCompare(name) == .orderedSame {
                errorMessage = NSLocalizedString("vaultNameExists", comment: "").replacingOccurrences(of: "%s", with: name)
                return
            }
        }
        errorMessage = ""
        isLinkActive = true
    }
    
    private func getVaultName() -> String {
        if name.isEmpty {
            return "Vault "
        } else {
            return name + " "
        }
    }
    
    private func resetPlaceholderName() {
        isNameFocused = false
        name = ""
        isNameFocused = true
    }
}

#Preview {
    NewWalletNameView(tssType: .Keygen, selectedTab: .fast, name: "Fast Vault #1")
}
