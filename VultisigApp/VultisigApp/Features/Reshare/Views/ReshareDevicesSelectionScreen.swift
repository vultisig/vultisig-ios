//
//  ReshareDevicesSelectionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/07/2026.
//

import SwiftUI
import RiveRuntime

/// Reshare step asking how many devices the new vault setup will use.
/// Reuses the onboarding devices component and gates selections that
/// would drop below the vault's required number of active signers.
struct ReshareDevicesSelectionScreen: View {
    let vault: Vault

    @StateObject private var viewModel: ReshareDevicesSelectionViewModel
    @State private var animationVM: RiveViewModel? = nil

    @Environment(\.router) var router

    init(vault: Vault) {
        self.vault = vault
        _viewModel = StateObject(wrappedValue: ReshareDevicesSelectionViewModel(
            currentDeviceCount: vault.signers.count,
            requiredActiveSigners: vault.getThreshold()
        ))
    }

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                animationVM?.view()
                    .frame(maxWidth: 400)
                    .overlay(alignment: .bottom) {
                        if !viewModel.isThresholdMet {
                            thresholdWarningCard
                        }
                    }
                Spacer()

                VStack(spacing: 16) {
                    tipView
                    // Disabled while FastVault eligibility loads so the
                    // 1-device path can't navigate with a stale default.
                    PrimaryButton(
                        title: "getStarted".localized,
                        isLoading: viewModel.isLoading,
                        action: onContinue
                    )
                    .disabled(!viewModel.isThresholdMet || viewModel.isLoading)
                }
            }
            .padding(.top, 64)
        }
        .screenIgnoresTopEdge()
        .screenBackground(.clear)
        .background(DevicesSelectionBackground())
        .onLoad(perform: onLoad)
        .task {
            await viewModel.load(vault: vault)
        }
    }

    var tipView: some View {
        HStack(spacing: 8) {
            Icon(named: "lightbulb", size: 12)
            Text("seedPhraseImportTip".localized)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.caption12)
        }
    }

    var thresholdWarningCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Icon(
                named: "triangle-alert",
                color: Theme.colors.alertWarning,
                size: 24
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("thresholdNotMetTitle".localized)
                    .font(Theme.fonts.subtitle)
                    .foregroundStyle(Theme.colors.textPrimary)

                Text(viewModel.thresholdWarningText)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(Theme.colors.bgPrimary)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 24)
    }

    private func onLoad() {
        animationVM = RiveViewModel(fileName: "devices_component")
        animationVM?.fit = .layout

        animationVM?.riveModel?.enableAutoBind { instance in
            instance.numberProperty(fromPath: "Index")?.addListener { value in
                viewModel.selectedIndex = Int(value)
                #if os(iOS)
                HapticFeedbackManager.shared.startHapticFeedback(duration: 0.1)
                #endif
            }
        }
    }

    private func onContinue() {
        switch viewModel.destination {
        case .fastVaultPassword(let isExistingVault):
            router.navigate(to: KeygenRoute.fastVaultPassword(
                tssType: .Reshare,
                vault: vault,
                selectedTab: .secure,
                isExistingVault: isExistingVault,
                singleKeygenType: nil
            ))
        case .peerDiscovery(let setupType):
            router.navigate(to: KeygenRoute.peerDiscovery(
                tssType: .Reshare,
                vault: vault,
                selectedTab: .secure,
                fastSignConfig: nil,
                keyImportInput: nil,
                setupType: setupType,
                singleKeygenType: nil
            ))
        }
    }
}

#Preview {
    ReshareDevicesSelectionScreen(vault: Vault.example)
}
