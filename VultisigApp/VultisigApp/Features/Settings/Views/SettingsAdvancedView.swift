//
//  SettingsAdvancedView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-12-16.
//

import SwiftUI

struct SettingsAdvancedView: View {
    let vault: Vault

    @EnvironmentObject var settingsViewModel: SettingsViewModel

    /// Resolved once on load via the shared `TierGate`. The swap provider-selection
    /// toggle is a Silver-tier (and above) entitlement, so its row stays hidden for
    /// vaults below Silver — keeping the gate and the swap VM's runtime check aligned.
    @State private var isSwapProviderSelectionUnlocked = false

    var body: some View {
        Screen {
            content
        }
        .screenTitle("advanced".localized)
        .task {
            isSwapProviderSelectionUnlocked = await TierGate().isUnlocked(.silver, for: vault)
        }
    }

    var content: some View {
        VStack {
            SettingToggleCell(
                title: "ETH Testnet(Sepolia)",
                icon: "timelapse",
                isEnabled: $settingsViewModel.enableSepolia
            )

            SettingToggleCell(
                title: "THORChain Stagenet",
                icon: "timelapse",
                isEnabled: $settingsViewModel.enableThorchainChainnet
            )

            SettingToggleCell(
                title: "Sell",
                icon: "creditcard",
                isEnabled: $settingsViewModel.sellEnabled
            )

            SettingToggleCell(
                title: "TSS Batching",
                icon: "bolt.horizontal",
                isEnabled: $settingsViewModel.tssBatchEnabled
            )

            if isSwapProviderSelectionUnlocked {
                SettingToggleCell(
                    title: "settingsAdvancedSwapProviderSelection".localized,
                    icon: "arrow.left.arrow.right",
                    isEnabled: $settingsViewModel.swapProviderSelectionEnabled
                )
            }

            SettingPickerCell(
                title: "settingsAdvancedForcedSwapProvider".localized,
                icon: "arrow.triangle.branch",
                options: [
                    .init(value: "", label: "settingsAdvancedForcedSwapProviderAll".localized),
                    .init(value: "swapkit", label: "SwapKit only"),
                    .init(value: "oneInch", label: "1Inch only"),
                    .init(value: "kyberSwap", label: "KyberSwap only"),
                    .init(value: "lifi", label: "LI.FI only"),
                    .init(value: "thorchain", label: "THORChain only"),
                    .init(value: "mayachain", label: "Maya only")
                ],
                selection: $settingsViewModel.forcedSwapProvider
            )

            SettingActionCell(
                title: "settingsAdvancedSwapKitClearTokensCache".localized,
                icon: "arrow.clockwise",
                buttonLabel: "settingsAdvancedClear".localized
            ) {
                SwapKitTokensCache.shared.clearCache()
            }
        }
    }
}

#Preview {
    ZStack {
        Background()
        SettingsAdvancedView(vault: .example)
    }
    .environmentObject(SettingsViewModel())
    .environmentObject(AppViewModel.shared)
}
