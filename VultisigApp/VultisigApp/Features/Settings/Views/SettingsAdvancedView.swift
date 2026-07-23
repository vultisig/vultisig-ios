//
//  SettingsAdvancedView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-12-16.
//

import SwiftUI

struct SettingsAdvancedView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @StateObject private var viewModel = SettingsAdvancedViewModel()

    var body: some View {
        Screen {
            content
        }
        .screenTitle("advanced".localized)
        .alert(
            "settingsAdvancedResetTransactionHistoryConfirmTitle".localized,
            isPresented: $viewModel.isConfirmingReset
        ) {
            Button("settingsAdvancedResetTransactionHistoryButton".localized, role: .destructive) {
                viewModel.confirmReset()
            }
            Button("cancel".localized, role: .cancel) {}
        } message: {
            Text("settingsAdvancedResetTransactionHistoryConfirmMessage".localized)
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

            SettingToggleCell(
                title: "limitSwapToggle".localized,
                icon: "arrow.up.right.square",
                isEnabled: $settingsViewModel.limitSwapEnabled
            )

            SettingPickerCell(
                title: "settingsAdvancedForcedSwapProvider".localized,
                icon: "arrow.triangle.branch",
                options: [
                    .init(value: "", label: "settingsAdvancedForcedSwapProviderAll".localized),
                    .init(value: "swapkit", label: "SwapKit only"),
                    .init(value: "oneInch", label: "1Inch only"),
                    .init(value: "kyberSwap", label: "KyberSwap only"),
                    .init(value: "lifi", label: "LI.FI only"),
                    .init(value: "jupiter", label: "settingsAdvancedForcedSwapProviderJupiter".localized),
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

            SettingActionCell(
                title: "settingsAdvancedResetTransactionHistory".localized,
                icon: "trash",
                buttonLabel: "settingsAdvancedResetTransactionHistoryButton".localized,
                buttonType: .alert
            ) {
                viewModel.requestReset()
            }
        }
    }
}

#Preview {
    ZStack {
        Background()
        SettingsAdvancedView()
    }
    .environmentObject(SettingsViewModel())
    .environmentObject(AppViewModel.shared)
}
