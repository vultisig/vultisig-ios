//
//  SettingsAdvancedView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-12-16.
//

import SwiftUI

struct SettingsAdvancedView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.router) var router

    @State private var isCustomRPCUnlocked = false

    var body: some View {
        Screen {
            content
        }
        .screenTitle("advanced".localized)
        .task {
            guard let vault = appViewModel.selectedVault else { return }
            isCustomRPCUnlocked = await TierGate().isUnlocked(.silver, for: vault)
        }
    }

    var content: some View {
        VStack {
            if isCustomRPCUnlocked {
                SettingActionCell(
                    title: "settingsAdvancedCustomRPC".localized,
                    icon: "network",
                    buttonLabel: "settingsAdvancedManage".localized
                ) {
                    router.navigate(to: SettingsRoute.customRPC)
                }
            }

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
                title: "MLDSA",
                icon: "lock.shield",
                isEnabled: $settingsViewModel.isMLDSAEnabled
            )

            SettingToggleCell(
                title: "TSS Batching",
                icon: "bolt.horizontal",
                isEnabled: $settingsViewModel.tssBatchEnabled
            )

            SettingToggleCell(
                title: "settingsAdvancedSwapKitToggle".localized,
                icon: "arrow.triangle.swap",
                isEnabled: $settingsViewModel.swapkitEnabled
            )

            SettingToggleCell(
                title: "settingsAdvancedQBTCClaimToggle".localized,
                icon: "lock.shield",
                isEnabled: $settingsViewModel.qbtcEnabled
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
        SettingsAdvancedView()
    }
    .environmentObject(SettingsViewModel())
    .environmentObject(AppViewModel.shared)
}
