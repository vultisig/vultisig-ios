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
    @State private var detents: [PresentationDetent] = []
    
    var minDetent: PresentationDetent {
        .height(340)
    }

    private enum Step {
        case welcome
        case vaultOptIn
    }

    var allVaultsEnabled: Bool {
        !vaults.isEmpty && vaults.allSatisfy { pushNotificationManager.isVaultOptedIn($0) }
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
        .presentationDetents(Set(detents))
        .presentationDragIndicator(.visible)
        .presentationCompactAdaptation(.none)
        .presentationBackground { Theme.colors.bgPrimary.padding(.bottom, -1000) }
        .background(Theme.colors.bgPrimary)
        .onLoad { detents = [minDetent] }
    }

    // MARK: - Welcome

    var welcomeContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                VaultSetupStepIcon(state: .active, icon: "bell")
                    .padding(.vertical, 8)
                Text("notificationsAreHere".localized)
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
                        if granted && !vaults.isEmpty {
                            updateDetentsForVaultOptIn()
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
                .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                SettingsSectionView(title: .empty) {
                    SettingsOptionView(
                        icon: nil,
                        title: "enableAll".localized,
                        subtitle: nil,
                        type: .highlighted,
                        showSeparator: true
                    ) {
                        VultiToggle(isOn: Binding(
                            get: { allVaultsEnabled },
                            set: {
                                pushNotificationManager.setAllVaultsOptIn(
                                    vaults, enabled: $0
                                )
                            }
                        ))
                    }

                    ForEach(vaults, id: \.id) { vault in
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

    private func updateDetentsForVaultOptIn() {
        let elementsCount = vaults.count + 1 // +1 for "Enable all" row
        switch elementsCount {
        case 1:
            detents = [minDetent]
        case 2:
            detents = [.height(278)]
        case 3:
            detents = [.medium]
        default:
            detents = isIPadOS ? [.large] : [.medium, .large]
        }
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
