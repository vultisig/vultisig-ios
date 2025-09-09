//
//  VaultMainScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 09/09/2025.
//

import SwiftUI

struct VaultMainScreen: View {
    let vault: Vault
    
    var body: some View {
        ZStack(alignment: .top) {
            VStack {
                Spacer()
            }
            VaultMainHeaderView(
                vault: vault,
                vaultSelectorAction: onVaultSelector,
                settingsAction: onSettings
            )
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VaultMainScreenBackground())
    }
    
    func onVaultSelector() {
        
    }
    
    func onSettings() {
        
    }
}

#Preview {
    VaultMainScreen(vault: .example)
}
