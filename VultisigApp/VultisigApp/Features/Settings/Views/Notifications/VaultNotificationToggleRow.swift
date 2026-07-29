//
//  VaultNotificationToggleRow.swift
//  VultisigApp
//

import SwiftUI

struct VaultNotificationToggleRow: View {
    let vault: Vault
    @EnvironmentObject var pushNotificationManager: PushNotificationManager

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { pushNotificationManager.isVaultOptedIn(vault) },
            set: { pushNotificationManager.setVaultOptIn(vault, enabled: $0) }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            VaultIconTypeView(isFastVault: vault.isFastVault)
                .padding(12)
                .overlay(Circle().stroke(Theme.colors.borderLight, lineWidth: 1))

            Text(vault.name)
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.textPrimary)

            Spacer()

            VultiToggle(isOn: isEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#if DEBUG
#Preview {
    VaultNotificationToggleRow(vault: Vault.example)
        .environmentObject(PushNotificationManager())
}
#endif
