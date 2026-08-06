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

    /// The debug rows this screen shows, ordered, so each one can tell the
    /// shared list container where it sits.
    enum Row: CaseIterable {
        case sepolia
        case thorchainStagenet
        case sell
        case tssBatching
        case passcode
        case forcedSwapProvider
        case clearSwapKitTokensCache
        case resetTransactionHistory
    }

    var content: some View {
        VStack(spacing: 0) {
            ForEach(Array(Row.allCases.enumerated()), id: \.element) { index, row in
                view(for: row)
                    .commonListItemContainer(index: index, itemsCount: Row.allCases.count)
            }
        }
        .commonListContainer()
    }

    @ViewBuilder
    func view(for row: Row) -> some View {
        switch row {
        case .sepolia:
            SettingToggleCell(
                title: "ETH Testnet(Sepolia)",
                icon: "timelapse",
                isEnabled: $settingsViewModel.enableSepolia
            )
        case .thorchainStagenet:
            SettingToggleCell(
                title: "THORChain Stagenet",
                icon: "timelapse",
                isEnabled: $settingsViewModel.enableThorchainChainnet
            )
        case .sell:
            SettingToggleCell(
                title: "Sell",
                icon: "creditcard",
                isEnabled: $settingsViewModel.sellEnabled
            )
        case .tssBatching:
            SettingToggleCell(
                title: "TSS Batching",
                icon: "bolt.horizontal",
                isEnabled: $settingsViewModel.tssBatchEnabled
            )
        case .passcode:
            SettingToggleCell(
                title: "Passcode",
                icon: "lock",
                isEnabled: $settingsViewModel.passcodeFeatureEnabled
            )
        case .forcedSwapProvider:
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
        case .clearSwapKitTokensCache:
            SettingActionCell(
                title: "settingsAdvancedSwapKitClearTokensCache".localized,
                icon: "arrow.clockwise",
                buttonLabel: "settingsAdvancedClear".localized
            ) {
                SwapKitTokensCache.shared.clearCache()
            }
        case .resetTransactionHistory:
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
