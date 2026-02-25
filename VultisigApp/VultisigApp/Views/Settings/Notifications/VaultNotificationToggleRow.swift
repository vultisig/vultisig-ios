//
//  VaultNotificationToggleRow.swift
//  VultisigApp
//

import SwiftUI

struct VaultNotificationToggleRow: View {
    let vault: Vault
    let showSeparator: Bool
    @EnvironmentObject var pushNotificationManager: PushNotificationManager

    @State private var isEnabled: Bool = false
    
    init(vault: Vault, showSeparator: Bool = false) {
        self.vault = vault
        self.showSeparator = showSeparator
    }

    var body: some View {
        SettingsOptionView(
            icon: nil,
            title: vault.name,
            subtitle: nil,
            type: .normal,
            showSeparator: showSeparator
        ) {
            VultiToggle(isOn: $isEnabled)
        }
        .onAppear {
            isEnabled = pushNotificationManager.isVaultOptedIn(
                pubKeyECDSA: vault.pubKeyECDSA
            )
        }
        .onChange(of: isEnabled) { _, newValue in
            pushNotificationManager.setVaultOptIn(vault: vault, enabled: newValue)
        }
    }
}

#if DEBUG
#Preview {
    VaultNotificationToggleRow(vault: Vault.example, showSeparator: false)
        .environmentObject(
            MockPushNotificationManager(permissionGranted: true)
                as PushNotificationManager
        )
}
#endif
