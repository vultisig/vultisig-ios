//
//  NotificationsIntroSheet.swift
//  VultisigApp
//

import SwiftData
import SwiftUI

struct NotificationsIntroSheet: View {
    @Binding var isPresented: Bool
    @Query var vaults: [Vault]
    @EnvironmentObject var pushNotificationManager: PushNotificationManager

    @State private var step: Step = .welcome

    private enum Step {
        case welcome
        case vaultOptIn
    }

    var secureVaults: [Vault] {
        vaults.filter { !$0.isFastVault }
    }

    var body: some View {
        VStack(spacing: 24) {
            Group {
                switch step {
                case .welcome:
                    welcomeContent
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

    // MARK: - Welcome

    var welcomeContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Text("notificationsAreHere".localized)
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
                        if granted && !secureVaults.isEmpty {
                            withAnimation(.interpolatingSpring) {
                                step = .vaultOptIn
                            }
                        } else {
                            dismiss()
                        }
                    }
                }

                PrimaryButton(title: "notNow", type: .secondary) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Vault Opt-In

    var vaultOptInContent: some View {
        VStack(spacing: 24) {
            Text("chooseVaultsForNotifications".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(secureVaults, id: \.id) { vault in
                        VaultNotificationToggleRow(vault: vault)
                    }
                }
            }

            Spacer()

            PrimaryButton(title: "done") {
                dismiss()
            }
        }
    }

    // MARK: - Private

    private func dismiss() {
        pushNotificationManager.hasSeenNotificationPrompt = true
        isPresented = false
    }
}

#if DEBUG
#Preview {
    NotificationsIntroSheet(isPresented: .constant(true))
        .environmentObject(
            MockPushNotificationManager(permissionGranted: false)
                as PushNotificationManager
        )
}
#endif
