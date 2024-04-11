//
//  SettingsOptionsStore.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import Foundation

enum SettingsLanguage: String, CaseIterable {
    case English
    case Deutsch
    case Espanol
    case Italiano
    case Hrvatski
    
    func description() -> String {
        let value: String
        
        switch self {
        case .English:
            value = "English (UK)"
        case .Deutsch:
            value = "German"
        case .Espanol:
            value = "Spanish"
        case .Italiano:
            value = "Italian"
        case .Hrvatski:
            value = "Croatian"
        }
        return value
    }
}


import Foundation

enum SettingsCurrency: String, CaseIterable {
    case USD
    case AUD
    
    static var current: SettingsCurrency {
        get {
            if let currencyString = UserDefaults.standard.string(forKey: "currency"),
               let currency = SettingsCurrency(rawValue: currencyString) {
                return currency
            } else {
                return .USD
            }
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "currency")
        }
    }
}

class SettingsOptionsStore {
    static let FAQData : [(question: String, answer: String)] = [
        (question: "setupVaultFAQQuestion", answer: "setupVaultFAQQuestion"),
        (question: "supportedCryptoFAQQuestion", answer: "supportedCryptoFAQQuestion"),
        (question: "vaultSecurityFAQQuestion", answer: "vaultSecurityFAQQuestion"),
        (question: "assetRecoveryFAQQuestion", answer: "assetRecoveryFAQQuestion"),
        (question: "transactionFeesFAQQuestion", answer: "transactionFeesFAQQuestion")
    ]
}
