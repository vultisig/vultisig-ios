//
//  SettingsAdvancedView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-12-16.
//

import SwiftUI

struct SettingsAdvancedView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel

    var body: some View {
        ZStack {
            Background()
            container
        }
    }

    var content: some View {
        VStack {
            SettingToggleCell(
                title: "enableDKLS",
                icon: "timelapse",
                isEnabled: $settingsViewModel.isDKLSEnabled
            )

            SettingToggleCell(
                title: "Swap",
                icon: "arrow.2.squarepath",
                isEnabled: $settingsViewModel.allowSwap
            )

            SettingToggleCell(
                title: "ETH Testnet(Sepolia)",
                icon: "timelapse",
                isEnabled: $settingsViewModel.enableSepolia
            )

            SettingToggleCell(
                title: "THORChain Stagenet",
                icon: "timelapse",
                isEnabled: $settingsViewModel.enableThorchainStagenet
            )

            SettingToggleCell(
                title: "Buy",
                icon: "creditcard",
                isEnabled: $settingsViewModel.buyEnabled
            )

            SettingToggleCell(
                title: "Sell",
                icon: "creditcard",
                isEnabled: $settingsViewModel.sellEnabled
            )
        }
    }
}

#Preview {
    ZStack {
        Background()
        SettingsAdvancedView()
    }
    .environmentObject(SettingsViewModel())
}
