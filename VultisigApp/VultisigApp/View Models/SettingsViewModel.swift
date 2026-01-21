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
    @AppStorage("thorchainStagenet") var enableThorchainStagenet: Bool = false
    @AppStorage("SellEnabled") var sellEnabled: Bool = false

    init() {
        self.selectedCurrency = SettingsCurrency.current
        self.selectedLanguage = SettingsLanguage.current
        self.selectedAPRPeriod = SettingsAPRPeriod.current
    }

    static let shared = SettingsViewModel()
}
