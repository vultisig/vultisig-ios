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

    @Environment(\.router) var router

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
            Button {
                router.navigate(to: VaultRoute.reshare(vault: vault))
            } label: {
                SettingsCommonOptionView(icon: "share", title: "reshare".localized, subtitle: "reshareVault".localized)
            }
        }
    }

    var customMessageRow: some View {
        Button {
            router.navigate(to: VaultRoute.customMessage(vault: vault))
        } label: {
            SettingsCommonOptionView(icon: "file-pen-line", title: "sign".localized, subtitle: "signCustomMessage".localized)
        }
    }

    var onChainSecurityRow: some View {
        Button {
            router.navigate(to: VaultRoute.onChainSecurity)
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
