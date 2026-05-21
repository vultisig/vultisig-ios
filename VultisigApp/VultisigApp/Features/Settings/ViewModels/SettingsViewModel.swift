//
//  SettingsViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var selectedLanguage: SettingsLanguage {
        didSet {
            SettingsLanguage.current = selectedLanguage
        }
    }

    @Published var selectedCurrency: SettingsCurrency {
        didSet {
            SettingsCurrency.current = selectedCurrency
        }
    }

    @Published var selectedAPRPeriod: SettingsAPRPeriod {
        didSet {
            SettingsAPRPeriod.current = selectedAPRPeriod
        }
    }

    @AppStorage("isDKLSEnabled") var isDKLSEnabled: Bool = false
    @AppStorage("allowSwap") var allowSwap: Bool = false
    @AppStorage("BuyEnabled") var buyEnabled: Bool = false
    @AppStorage("sepolia") var enableSepolia: Bool = false
    @AppStorage("thorchainChainnet") var enableThorchainChainnet: Bool = false
    @AppStorage("SellEnabled") var sellEnabled: Bool = false
    @AppStorage("isMLDSAEnabled") var isMLDSAEnabled: Bool = false
    @AppStorage("tssBatchEnabled") var tssBatchEnabled: Bool = false
    @AppStorage("swapkitEnabled") var swapkitEnabled: Bool = false
    /// Debug-only: force every swap quote through a single provider so a
    /// tester can verify a specific signing path in isolation. Empty string
    /// = no force (production ranking across all providers). Otherwise one
    /// of: "swapkit", "oneInch", "kyberSwap", "lifi", "thorchain",
    /// "mayachain". `Coin+Swaps.swapProviders` reads this and filters the
    /// natural provider list down to the single forced provider.
    @AppStorage("forcedSwapProvider") var forcedSwapProvider: String = ""

    init() {
        self.selectedCurrency = SettingsCurrency.current
        self.selectedLanguage = SettingsLanguage.current
        self.selectedAPRPeriod = SettingsAPRPeriod.current
    }

    static let shared = SettingsViewModel()
}
