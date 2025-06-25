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

    @State var didSet = false
    @State var isLinkActive = false
    @State var showAlert = false
    @FocusState private var isNameFocused: Bool
    
    @Query var vaults: [Vault]
    
    var body: some View {
        content
    }
    
    var view: some View {
        VStack {
            fields
            Spacer()
            button
        }
        .onAppear() {
            isNameFocused = true
        }
        .alert(isPresented: $showAlert) {
            alert
        }
    }
    
    var textfield: some View {
        HStack {
            TextField(NSLocalizedString("enterVaultName", comment: "").capitalized, text: $name)
                .font(.body16BrockmannMedium)
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
                .stroke(Color.blue200, lineWidth: 1)
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
        Button {
            verifyVault()
        } label: {
            FilledButton(title: "next")
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
    
    var alert: Alert {
        Alert(
            title: Text(getVaultName() + NSLocalizedString("alreadyExists", comment: "")),
            message: Text(NSLocalizedString("vaultNameUnique", comment: "")),
            dismissButton: .default(Text(NSLocalizedString("dismiss", comment: "")))
        )
    }
    
    var fields: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("nameYourVault", comment: ""))
                .font(.body34BrockmannMedium)
                .foregroundColor(.neutral0)
                .padding(.top, 16)
            
            Text(NSLocalizedString("newWalletNameDescription", comment: ""))
                .font(.body14BrockmannMedium)
                .foregroundColor(.extraLightGray)
            
            textfield
        }
        .padding(.horizontal, 16)
    }

    private func verifyVault() {
        for vault in vaults {
            if name.isEmpty || vault.name == name {
                showAlert = true
                return
            }
        }
        
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
        guard !didSet else {
            return
        }
        
        name = ""
        didSet = true
    }
}

#Preview {
    NewWalletNameView(tssType: .Keygen, selectedTab: .fast, name: "Fast Vault #1")
}
