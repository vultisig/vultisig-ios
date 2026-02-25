//
//  NotificationSetupSheet.swift
//  VultisigApp
//

import SwiftUI

struct NotificationSetupSheet: View {
    let vault: Vault
    @Binding var isPresented: Bool
    @EnvironmentObject var pushNotificationManager: PushNotificationManager

    @State private var step: Step = .permission

    private enum Step {
        case permission
        case vaultOptIn
    }

    var body: some View {
        VStack(spacing: 24) {
            Group {
                switch step {
                case .permission:
                    permissionContent
                case .vaultOptIn:
                    vaultOptInContent
                }
            }
            .transition(.opacity)
            .animation(.interpolatingSpring, value: step)
        }
        .padding(24)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .presentationCompactAdaptation(.none)
        .presentationBackground { Theme.colors.bgPrimary.padding(.bottom, -1000) }
        .background(Theme.colors.bgPrimary)
    }

    // MARK: - Permission

    var permissionContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Text("enablePushNotifications".localized)
                    .font(Theme.fonts.title2)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("notificationsDescription".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                PrimaryButton(title: "enablePushNotifications") {
                    Task {
                        let granted = await pushNotificationManager.requestPermission()
                        if granted {
                            withAnimation(.interpolatingSpring) {
                                step = .vaultOptIn
                            }
                        } else {
                            isPresented = false
                        }
                    }
                }

                PrimaryButton(title: "notNow", type: .secondary) {
                    isPresented = false
                }
            }
        }
    }

    // MARK: - Vault Opt-In

    var vaultOptInContent: some View {
        VStack(spacing: 24) {
            Text("enableNotificationsForVault".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)

            VaultNotificationToggleRow(vault: vault)

            Spacer()

            PrimaryButton(title: "done") {
                isPresented = false
            }
        }
    }
}

#if DEBUG
#Preview {
    let mock: PushNotificationManager = MockPushNotificationManager(
        permissionGranted: false
    )

    Screen {
        Color.clear
    }
    .crossPlatformSheet(isPresented: .constant(true)) {
        NotificationSetupSheet(
            vault: .example,
            isPresented: .constant(true)
        )
        .environmentObject(mock)
    }
    .environmentObject(mock)
}
#endif
