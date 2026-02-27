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

    var allVaultsEnabled: Bool {
        !vaults.isEmpty && vaults.allSatisfy { pushNotificationManager.isVaultOptedIn($0) }
    }

    var body: some View {
        Screen(title: "notifications".localized) {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    mainToggleSection
                    vaultListSection
                        .showIf(notificationsEnabled && !vaults.isEmpty)
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

            VultiToggle(isOn: Binding(
                get: { notificationsEnabled },
                set: {
                    guard $0 != notificationsEnabled else { return }
                    onNotificationsEnabled($0)
                }
            ))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    var vaultListSection: some View {
        SettingsSectionView(title: "vaultNotifications".localized) {
            SettingsOptionView(
                icon: nil,
                title: "enableAll".localized,
                subtitle: nil,
                type: .highlighted,
                showSeparator: true
            ) {
                VultiToggle(isOn: Binding(
                    get: { allVaultsEnabled },
                    set: { pushNotificationManager.setAllVaultsOptIn(vaults, enabled: $0) }
                ))
            }

            ForEach(vaults, id: \.id) { vault in
                VaultNotificationToggleRow(
                    vault: vault,
                    showSeparator: vault != vaults.last
                )
            }
        }
    }
    
    func onNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        if enabled {
            Task {
                let granted = await pushNotificationManager.requestPermission()
                if granted {
                    pushNotificationManager.setAllVaultsOptIn(vaults, enabled: true)
                } else {
                    notificationsEnabled = false
                }
            }
        } else {
            pushNotificationManager.setAllVaultsOptIn(vaults, enabled: false)
            pushNotificationManager.unregisterForRemoteNotifications()
        }
    }
}

#if DEBUG
#Preview {
    NotificationsSettingsScreen()
        .environmentObject(PushNotificationManager())
}
#endif
