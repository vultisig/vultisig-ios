//
//  VaultMainHeaderView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 09/09/2025.
//

import SwiftUI

struct VaultMainHeaderView: View {
    let vault: Vault
    var vaultSelectorAction: () -> Void
    var settingsAction: () -> Void
    
    var body: some View {
        HStack(spacing: 32) {
            VaultSelectorView(
                vaultName: vault.name,
                isFastVault: vault.isFastVault,
                action: vaultSelectorAction
            )
            Spacer()
            HStack(spacing: 8) {
                CircularIconButton(icon: "settings", action: settingsAction)
            }
        }
    }
}

#Preview {
    VStack {
        VaultMainHeaderView(vault: .example) {
            print("Vault Selector Action")
        } settingsAction: {
            print("Settings action")
        }
    }
    .background(Theme.colors.bgPrimary)
}
