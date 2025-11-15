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
                SettingsCommonOptionView(icon: "share", title: "reshare".localized, subtitle: "reshareVault".localized)
            }
        }
    }
    
    var customMessageRow: some View {
        NavigationLink {
            SettingsCustomMessageView(vault: vault)
        } label: {
            SettingsCommonOptionView(icon: "file-pen-line", title: "sign".localized, subtitle: "signCustomMessage".localized)
        }
    }
    
    var onChainSecurityRow: some View {
        NavigationLink {
            OnChainSecurityScreen()
        } label: {
            SettingsCommonOptionView(
                icon: "folder-lock",
                title: "vaultSettingsSecurityTitle".localized,
                subtitle: "vaultSettingsSecuritySubtitle".localized,
                showSeparator: false
            )
        }
    }
}
