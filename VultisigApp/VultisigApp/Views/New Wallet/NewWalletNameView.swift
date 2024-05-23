//
//  NewWalletNameView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-12.
//

import SwiftUI

struct NewWalletNameView: View {
    let tssType: TssType
    let vault: Vault?
    let selectedTab: SetupVaultState
    @State var name = ""
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("nameYourVault", comment: "Name your Vault"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
        }
    }
    
    var view: some View {
        VStack {
            content
            Spacer()
            button
        }
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("vaultName", comment: ""))
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)
            
            textfield
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
    }
    
    var textfield: some View {
        TextField(NSLocalizedString("mainVault", comment: "").capitalized, text: $name)
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .submitLabel(.done)
            .padding(12)
            .background(Color.blue600)
            .cornerRadius(12)
    }
    
    var button: some View {
        NavigationLink {
            let vaultName = name.isEmpty ? "Main Vault" : name
            PeerDiscoveryView(tssType: tssType, vault: Vault(name: vaultName), selectedTab: selectedTab)
        } label: {
            FilledButton(title: "continue")
        }
        .padding(40)
    }
}

#Preview {
    NewWalletNameView(tssType: .Keygen, vault: nil, selectedTab: .TwoOfTwoVaults)
}
