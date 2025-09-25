//
//  UpgradeVaultViewModifier.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 25/09/2025.
//

import SwiftUI

struct UpgradeVaultViewModifier: ViewModifier {
    let vault: Vault
    @Binding var shouldShow: Bool
    
    @State var upgradeYourVaultLinkActive: Bool = false
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $shouldShow) {
                UpgradeYourVaultView(
                    showSheet: $shouldShow,
                    navigationLinkActive: $upgradeYourVaultLinkActive
                )
            }
            .navigationDestination(isPresented: $upgradeYourVaultLinkActive, destination: {
                if vault.isFastVault {
                    VaultShareBackupsView(vault: vault)
                } else {
                    AllDevicesUpgradeView(vault: vault)
                }
            })
    }
}

extension View {
    func withUpgradeVault(vault: Vault, shouldShow: Binding<Bool>) -> some View {
        modifier(UpgradeVaultViewModifier(vault: vault, shouldShow: shouldShow))
    }
}
