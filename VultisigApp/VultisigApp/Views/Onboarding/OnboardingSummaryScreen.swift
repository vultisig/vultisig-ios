//
//  OnboardingSummaryScreen.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 08.02.2025.
//

import SwiftUI
import RiveRuntime

struct OnboardingSummaryScreen: View {
    let vault: Vault

    @EnvironmentObject var appViewModel: AppViewModel

    @State var animationVM: RiveViewModel? = nil
    @State var presentChainSelection: Bool = false

    var showChooseChainsButton: Bool {
        vault.libType != .KeyImport
    }

    var body: some View {
        Screen(edgeInsets: .init(leading: 0, trailing: 0)) {
            VStack(spacing: 0) {
                successAnimation
                bottomContent
                    .padding(.horizontal, 16)
            }
        }
        .onLoad(perform: onLoad)
        .crossPlatformSheet(isPresented: $presentChainSelection) {
            VaultSelectChainScreen(
                vault: vault,
                preselectChains: false,
                isPresented: $presentChainSelection
            ) {
                goToHome()
            }
        }
    }

    var successAnimation: some View {
        animationVM?.view()
            .scaleEffect(1.2)
            .frame(maxWidth: 500)
    }

    var bottomContent: some View {
        VStack(spacing: 48) {
            VStack(spacing: 24) {
                checkmarkIcon
                congratsText
            }
            buttons
        }
    }

    var checkmarkIcon: some View {
        Circle()
            .fill(Theme.colors.alertSuccess.opacity(0.05))
            .stroke(Theme.colors.borderExtraLight, lineWidth: 1.5)
            .frame(width: 40, height: 40)
            .overlay(
                Icon(
                    named: "shield-check-filled",
                    color: Theme.colors.alertSuccess,
                    size: 20
                )
            )
    }

    var congratsText: some View {
        VStack(spacing: 8) {
            Text(NSLocalizedString("congratsExclamation", comment: ""))
                .font(Theme.fonts.title2)
                .foregroundStyle(LinearGradient.primaryGradientHorizontal)

            Text(NSLocalizedString("yourVaultIsReadyToUse", comment: ""))
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)

            Text(NSLocalizedString("congratsSummaryDescription", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 321)
        }
    }

    var buttons: some View {
        VStack(spacing: 12) {
            goToWalletButton

            chooseChainsButton
                .showIf(showChooseChainsButton)
        }
    }

    var goToWalletButton: some View {
        PrimaryButton(title: "goToWallet") {
            goToHome()
        }
    }

    var chooseChainsButton: some View {
        PrimaryButton(title: "chooseChains", type: .secondary) {
            presentChainSelection = true
        }
    }

    private func goToHome() {
        appViewModel.set(selectedVault: vault)
    }

    private func onLoad() {
        animationVM = RiveViewModel(fileName: "onboarding_success")
        animationVM?.fit = .fitWidth
    }
}

#Preview {
    OnboardingSummaryScreen(
        vault: Vault.example
    ).environmentObject(HomeViewModel())
        .environmentObject(AppViewModel())
}
