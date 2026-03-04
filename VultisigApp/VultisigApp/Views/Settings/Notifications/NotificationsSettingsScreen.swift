//
//  NotificationsSettingsScreen.swift
//  VultisigApp
//

import SwiftData
import SwiftUI

struct NotificationsSettingsScreen: View {
    @Query var vaults: [Vault]
    @EnvironmentObject var pushNotificationManager: PushNotificationManager

    @Environment(\.scenePhase) private var scenePhase

    @State private var notificationsEnabled: Bool = false
    @State private var showSettingsAlert: Bool = false

    var allVaultsEnabled: Bool {
        !vaults.isEmpty && vaults.allSatisfy { pushNotificationManager.isVaultOptedIn($0) }
    }

    var body: some View {
        Screen(title: "notifications".localized) {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    mainToggleSection
                    vaultListSection
                        .transition(.verticalGrowAndFade)
                        .animation(.interpolatingSpring, value: notificationsEnabled && !vaults.isEmpty)
                        .showIf(notificationsEnabled && !vaults.isEmpty)
                }
            }
        }
        .onLoad { Task { await checkForPermissions() } }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await checkForPermissions() }
            }
        }
        .alert(
            "notificationsDisabledTitle".localized,
            isPresented: $showSettingsAlert
        ) {
            Button("openSettings".localized) {
                openSettings()
            }
            Button("cancel".localized, role: .cancel) {}
        } message: {
            Text("notificationsDisabledMessage".localized)
        }
    }

    var mainToggleSection: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("pushNotifications".localized)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)

                Text("pushNotificationsDescription".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .frame(maxWidth: 235, alignment: .leading)
            }.frame(maxWidth: .infinity, alignment: .leading)

            VultiToggle(isOn: Binding(
                get: { notificationsEnabled },
                set: {
                    guard $0 != notificationsEnabled else { return }
                    onNotificationsEnabled($0)
                }
            )).fixedSize()
        }
        .padding(.vertical, 8)
    }

    var vaultListSection: some View {
        SettingsSectionView(title: "vaultNotifications".localized) {
            enableAllView
                .showIf(vaults.count > 1)

            ForEach(vaults, id: \.id) { vault in
                VaultNotificationToggleRow(
                    vault: vault,
                    showSeparator: vault != vaults.last
                )
            }
        }
    }

    var enableAllView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Text("enableAll".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                Spacer()
                VultiToggle(isOn: Binding(
                    get: { allVaultsEnabled },
                    set: { pushNotificationManager.setAllVaultsOptIn(vaults, enabled: $0) }
                ))
            }
            .padding(.vertical, 16)
            Separator(color: Theme.colors.borderLight, opacity: 1)
        }
        .padding(.horizontal, 16)
    }

    func onNotificationsEnabled(_ enabled: Bool) {
        if enabled {
            Task {
                let status = await pushNotificationManager.authorizationStatus()
                if status == .denied {
                    notificationsEnabled = false
                    showSettingsAlert = true
                    return
                }

                let granted = await pushNotificationManager.requestPermission()
                if granted {
                    notificationsEnabled = true
                    pushNotificationManager.setAllVaultsOptIn(vaults, enabled: true)
                } else {
                    notificationsEnabled = false
                }
            }
        } else {
            notificationsEnabled = enabled
            pushNotificationManager.setAllVaultsOptIn(vaults, enabled: false)
            pushNotificationManager.unregisterForRemoteNotifications()
        }
    }

    private func openSettings() {
        #if os(iOS)
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    @MainActor
    func checkForPermissions() async {
        await pushNotificationManager.checkPermissionStatus()
        let isEnabled = pushNotificationManager.isPermissionGranted
        onNotificationsEnabled(isEnabled)
    }
}

#if DEBUG
#Preview {
    NotificationsSettingsScreen()
        .environmentObject(PushNotificationManager())
}
#endif
