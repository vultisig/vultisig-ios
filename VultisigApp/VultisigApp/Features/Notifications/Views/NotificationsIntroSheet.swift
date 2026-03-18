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

    var allVaultsEnabled: Bool {
        !vaults.isEmpty && vaults.allSatisfy { pushNotificationManager.isVaultOptedIn($0) }
    }

    var body: some View {
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
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .padding(.top, step == .welcome ? 0 : 24)
        .presentationDetents(Set(step == .welcome ? [.height(416)] : [.medium, .large]))
        .if(step == .welcome) {
            $0
                .edgesIgnoringSafeArea(.top)
                .presentationDragIndicator(.visible)
                .presentationCompactAdaptation(.none)
        }
        .presentationBackground { Theme.colors.bgSurface1.padding(.bottom, -1000) }
        .background(Theme.colors.bgSurface1)
    }

    // MARK: - Welcome

    var welcomeContent: some View {
        VStack(spacing: 36) {
            Image("notifications-intro")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 270)

            VStack(spacing: 0) {
                Text("notificationsAreHere".localized)
                    .font(Theme.fonts.title3)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)

                Text("notificationsDescription".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 321)
            }

            HStack(spacing: 12) {
                PrimaryButton(title: "notNow", type: .secondary) {
                    dismiss()
                }

                PrimaryButton(title: "enable") {
                    Task {
                        let granted = await pushNotificationManager.requestPermission()
                        if granted && vaults.count > 1 {
                            withAnimation(.interpolatingSpring) {
                                step = .vaultOptIn
                            }
                        } else {
                            if let vault = vaults.first {
                                pushNotificationManager.setVaultOptIn(vault, enabled: true)
                            }
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Vault Opt-In

    var vaultOptInContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Text("chooseVaultsForNotifications".localized)
                    .font(Theme.fonts.title3)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("manageNotificationsInSettings".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 320)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    enableAllView
                        .showIf(vaults.count > 1)
                    ForEach(vaults, id: \.id) { vault in
                        VaultNotificationToggleRow(vault: vault)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Theme.colors.bgSurface12)
                )
            }

            Spacer()

            PrimaryButton(title: "done") {
                dismiss()
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
                    set: {
                        pushNotificationManager.setAllVaultsOptIn(
                            vaults, enabled: $0
                        )
                    }
                ))
            }
            .padding(.vertical, 16)
            Separator(color: Theme.colors.borderLight, opacity: 1)
        }
        .padding(.horizontal, 16)
    }

    private func dismiss() {
        pushNotificationManager.hasSeenNotificationPrompt = true
        isPresented = false
    }
}

#if DEBUG
#Preview {
    NotificationsIntroSheet(isPresented: .constant(true))
        .environmentObject(PushNotificationManager())
}
#endif
