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
    
    @AppStorage("isDKLSEnabled") var isDKLSEnabled: Bool = false
    @AppStorage("allowSwap") var allowSwap: Bool = false
    @AppStorage("moonpayBuyEnabled") var moonpayBuyEnabled: Bool = false
    @AppStorage("moonpaySellEnabled") var moonpaySellEnabled: Bool = false
    
    init() {
        self.selectedCurrency = SettingsCurrency.current
        self.selectedLanguage = SettingsLanguage.current
    }
    
    static let shared = SettingsViewModel()
}
