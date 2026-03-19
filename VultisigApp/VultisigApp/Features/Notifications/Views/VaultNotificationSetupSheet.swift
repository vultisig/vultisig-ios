//
//  VaultNotificationSetupSheet.swift
//  VultisigApp
//

import SwiftUI

struct VaultNotificationSetupSheet: View {
    let vault: Vault
    @Binding var isPresented: Bool
    @EnvironmentObject var pushNotificationManager: PushNotificationManager

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                VaultSetupStepIcon(state: .active, icon: "bell")
                    .padding(.vertical, 8)
                Text("enablePushNotifications".localized)
                    .font(Theme.fonts.title2)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("notificationsDescription".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 321)
                    .fixedSize()
            }

            Spacer()

            VStack(spacing: 12) {
                PrimaryButton(title: "enablePushNotifications") {
                    Task {
                        let granted = await pushNotificationManager.requestPermission()
                        if granted {
                            pushNotificationManager.setVaultOptIn(vault, enabled: true)
                        }
                        pushNotificationManager.hasSeenNotificationPrompt = true
                        isPresented = false
                    }
                }

                PrimaryButton(title: "notNow", type: .secondary) {
                    isPresented = false
                }
            }
        }
        .padding(24)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
        .presentationCompactAdaptation(.none)
        .presentationBackground { Theme.colors.bgPrimary.padding(.bottom, -1000) }
        .background(Theme.colors.bgPrimary)
    }
}

#if DEBUG
#Preview {
    let mock = PushNotificationManager()

    Screen {
        Color.clear
    }
    .crossPlatformSheet(isPresented: .constant(true)) {
        VaultNotificationSetupSheet(
            vault: .example,
            isPresented: .constant(true)
        )
        .environmentObject(mock)
    }
    .environmentObject(mock)
}
#endif
