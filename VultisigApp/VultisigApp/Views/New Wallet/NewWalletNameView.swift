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
    let vault: Vault?
    let selectedTab: SetupVaultState
    
    @State var didSet = false
    @State var name = "Main Vault"
    @State var isLinkActive = false
    @State var showAlert = false
    
    @Query var vaults: [Vault]
    
    var body: some View {
        ZStack {
            Background()
            main
        }
#if os(iOS)
        .navigationTitle(NSLocalizedString("setup", comment: "Setup"))
        .toolbar {
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                NavigationHelpButton()
            }
        }
        .onTapGesture {
            hideKeyboard()
        }
#endif
    }
    
    var main: some View {
        VStack {
#if os(macOS)
            headerMac
#endif
            view
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "setup")
    }
    
    var view: some View {
        VStack {
            content
            Spacer()
            button
        }
        .alert(isPresented: $showAlert) {
            alert
        }
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("vaultName", comment: ""))
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)
            
            textfield
        }
#if os(iOS)
        .padding(.horizontal, 16)
#elseif os(macOS)
        .padding(.horizontal, 40)
#endif
        .padding(.top, 30)
    }
    
    var textfield: some View {
        TextField(NSLocalizedString("enterVaultName", comment: "").capitalized, text: $name)
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .submitLabel(.done)
            .padding(12)
            .background(Color.blue600)
            .cornerRadius(12)
            .colorScheme(.dark)
            .borderlessTextFieldStyle()
            .maxLength($name)
            .autocorrectionDisabled()
            .onTapGesture {
                resetPlaceholderName()
            }
    }
    
    var button: some View {
        Button {
            verifyVault()
        } label: {
            FilledButton(title: "continue")
        }
        .padding(40)
        .navigationDestination(isPresented: $isLinkActive) {
            let vaultName = name.isEmpty ? "Main Vault" : name
            let vault = Vault(name: vaultName)

            if selectedTab.isFastVault {
                FastVaultPasswordView(tssType: tssType, vault: vault, selectedTab: selectedTab)
            } else {
                PeerDiscoveryView(tssType: tssType, vault: vault, selectedTab: selectedTab, fastVaultPassword: nil)
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

    private func verifyVault() {
        for vault in vaults {
            if name.isEmpty && vault.name == "Main Vault" {
                showAlert = true
                return
            } else if vault.name == name {
                showAlert = true
                return
            }
        }
        
        isLinkActive = true
    }
    
    private func getVaultName() -> String {
        if name.isEmpty {
            return "Main Vault "
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
    NewWalletNameView(tssType: .Keygen, vault: nil, selectedTab: .fast)
}
