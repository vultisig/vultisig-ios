//
//  VaultNotificationToggleRow.swift
//  VultisigApp
//

import SwiftUI

struct VaultNotificationToggleRow: View {
    let vault: Vault
    let showSeparator: Bool
    @EnvironmentObject var pushNotificationManager: PushNotificationManager

    init(vault: Vault, showSeparator: Bool = false) {
        self.vault = vault
        self.showSeparator = showSeparator
    }

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { pushNotificationManager.isVaultOptedIn(vault) },
            set: { pushNotificationManager.setVaultOptIn(vault, enabled: $0) }
        )
    }

    var body: some View {
        SettingsOptionView(
            icon: nil,
            title: vault.name,
            subtitle: nil,
            type: .normal,
            showSeparator: showSeparator
        ) {
            VultiToggle(isOn: isEnabled)
        }
    }
}

#if DEBUG
#Preview {
    VaultNotificationToggleRow(vault: Vault.example, showSeparator: false)
        .environmentObject(PushNotificationManager())
}
#endif
