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
        VStack(spacing: 0) {
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
            .padding(.vertical, 12)

            Separator(color: Theme.colors.borderLight, opacity: 1)
                .showIf(showSeparator)
        }
        .padding(.horizontal, 16)
    }
}

#if DEBUG
#Preview {
    VaultNotificationToggleRow(vault: Vault.example, showSeparator: false)
        .environmentObject(PushNotificationManager())
}
#endif
