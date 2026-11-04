//
//  VaultNotificationToggleRow.swift
//  VultisigApp
//

import SwiftUI

struct VaultNotificationToggleRow: View {
    /// `.settings` is the Notifications screen's row; the intro sheet keeps `.standard`.
    enum Style {
        case standard, settings
    }

    let vault: Vault
    var style: Style = .standard
    @EnvironmentObject var pushNotificationManager: PushNotificationManager

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { pushNotificationManager.isVaultOptedIn(vault) },
            set: { pushNotificationManager.setVaultOptIn(vault, enabled: $0) }
        )
    }

    var body: some View {
        switch style {
        case .standard:
            HStack(spacing: 12) {
                VaultIconTypeView(isFastVault: vault.offersFastSigning)
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
        case .settings:
            HStack(spacing: 12) {
                // Sized to the toggle so the row keeps the design's height with the icon in it.
                VaultIconTypeView(isFastVault: vault.offersFastSigning)
                    .padding(7)
                    .overlay(Circle().strokeBorder(Theme.colors.borderLight, lineWidth: 1))

                Text(vault.name)
                    .settingsText(.bodyS)
                    .foregroundStyle(Theme.colors.textPrimary)

                Spacer(minLength: 4)

                Toggle(vault.name, isOn: isEnabled)
                    .toggleStyle(SettingsToggleStyle(size: .regular))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
        }
    }
}

#if DEBUG
#Preview {
    VaultNotificationToggleRow(vault: Vault.example)
        .environmentObject(PushNotificationManager())
}
#endif
