//
//  ReshareDevicesSelectionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/07/2026.
//

import SwiftUI

/// Reshare step asking how many devices the new vault setup will use.
/// Reuses the shared devices selector and gates selections that would drop
/// below the vault's required number of active signers.
struct ReshareDevicesSelectionScreen: View {
    let vault: Vault

    @StateObject private var viewModel: ReshareDevicesSelectionViewModel

    @Environment(\.router) var router

    init(vault: Vault) {
        self.vault = vault
        _viewModel = StateObject(wrappedValue: ReshareDevicesSelectionViewModel(
            currentDeviceCount: vault.signers.count,
            requiredActiveSigners: vault.getThreshold()
        ))
    }

    var body: some View {
        // Disabled while FastVault eligibility loads so the 1-device path
        // can't navigate with a stale default.
        DevicesSelectionView(
            selectedIndex: $viewModel.selectedIndex,
            tipText: "seedPhraseImportTip".localized,
            buttonTitle: "getStarted".localized,
            isLoading: viewModel.isLoading,
            isButtonDisabled: !viewModel.isThresholdMet || viewModel.isLoading,
            onContinue: onContinue
        ) {
            if !viewModel.isThresholdMet {
                thresholdWarningCard
            }
        }
        .task {
            await viewModel.load(vault: vault)
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
