//
//  VaultAdvancedSettingsScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/08/2025.
//

import SwiftUI
import SwiftData

struct VaultAdvancedSettingsScreen: View {
    let vault: Vault
    
    var body: some View {
        Screen(title: "advanced".localized) {
            ScrollView(showsIndicators: false) {
                SettingsSectionContainerView {
                    VStack(spacing: 0) {
                        reshareVaultRow
                        customMessageRow
                        onChainSecurityRow
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    var reshareVaultRow: some View {
        if !vault.isFastVault {
            NavigationLink {
                ReshareView(vault: vault)
            } label: {
                SettingsOptionView(icon: "share", title: "reshare".localized, subtitle: "reshareVault".localized)
            }
        }
    }
    
    var customMessageRow: some View {
        NavigationLink {
            SettingsCustomMessageView(vault: vault)
        } label: {
            SettingsOptionView(icon: "file-pen-line", title: "Sign", subtitle: "Sign custom message")
        }
    }
    
    var onChainSecurityRow: some View {
        NavigationLink {
            OnChainSecurityScreen()
        } label: {
            SettingsOptionView(
                icon: "folder-lock",
                title: "vaultSettingsSecurityTitle".localized,
                subtitle: "vaultSettingsSecuritySubtitle".localized,
                showSeparator: false
            )
        }
    }
}
