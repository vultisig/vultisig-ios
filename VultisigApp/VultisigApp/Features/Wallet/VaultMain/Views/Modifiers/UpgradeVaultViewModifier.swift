//
//  UpgradeVaultViewModifier.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 25/09/2025.
//

import SwiftUI

struct UpgradeVaultViewModifier: ViewModifier {
    @Environment(\.router) var router
    let vault: Vault
    @Binding var shouldShow: Bool

    func body(content: Content) -> some View {
        content
            .crossPlatformSheet(isPresented: $shouldShow) {
                UpgradeYourVaultView(
                    showSheet: $shouldShow,
                    onUpgrade: {
                        router.navigate(to: VaultRoute.upgradeVault(
                            vault: vault,
                            isFastVault: vault.isFastVault
                        ))
                    }
                )
            }
    }
}

extension View {
    func withUpgradeVault(vault: Vault, shouldShow: Binding<Bool>) -> some View {
        modifier(UpgradeVaultViewModifier(vault: vault, shouldShow: shouldShow))
    }
}
