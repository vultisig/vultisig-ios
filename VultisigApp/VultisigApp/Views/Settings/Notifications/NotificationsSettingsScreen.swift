//
//  NotificationsSettingsScreen.swift
//  VultisigApp
//

import SwiftData
import SwiftUI

struct NotificationsSettingsScreen: View {
    @Query var vaults: [Vault]
    @EnvironmentObject var pushNotificationManager: PushNotificationManager

    @State private var notificationsEnabled: Bool = false

    var secureVaults: [Vault] {
        vaults.filter { !$0.isFastVault }
    }

    var body: some View {
        Screen(title: "notifications".localized) {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    mainToggleSection
                    vaultListSection
                        .showIf(notificationsEnabled && !secureVaults.isEmpty)
                }
            }
        }
        .onAppear {
            notificationsEnabled = pushNotificationManager.isPermissionGranted
        }
    }

    var mainToggleSection: some View {
        HStack {
            Text("enablePushNotifications".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            Spacer()

            VultiToggle(isOn: $notificationsEnabled)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .onChange(of: notificationsEnabled) { _, newValue in
            if newValue {
                Task {
                    let granted = await pushNotificationManager.requestPermission()
                    if !granted {
                        notificationsEnabled = false
                    }
                }
            }
        }
    }

    var vaultListSection: some View {
        SettingsSectionView(title: "vaultNotifications".localized) {
            ForEach(secureVaults, id: \.id) { vault in
                VaultNotificationToggleRow(vault: vault, showSeparator: vault != secureVaults.last)
            }
        }
    }
}

#if DEBUG
#Preview {
    NotificationsSettingsScreen()
        .environmentObject(PushNotificationManager())
}
#endif
