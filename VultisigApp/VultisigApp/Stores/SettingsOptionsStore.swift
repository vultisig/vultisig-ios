//
//  SettingsOptionsStore.swift
//  VultisigApp
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
    case Portuguese
    
    func description() -> String {
        switch self {
        case .English:
            return NSLocalizedString("EnglishUK", comment: "English (UK)")
        case .Deutsch:
            return NSLocalizedString("German", comment: "German")
        case .Espanol:
            return NSLocalizedString("Spanish", comment: "Spanish")
        case .Italiano:
            return NSLocalizedString("Italian", comment: "Italian")
        case .Hrvatski:
            return NSLocalizedString("Croatian", comment: "Croatian")
        case .Portuguese:
            return NSLocalizedString("Portuguese", comment: "Portuguese")
        }
    }
    
    func appleLanguageCode() -> String {
        switch self {
        case .English:
            return "en" // Assuming UK English; use "en" or "en-US" for American English
        case .Deutsch:
            return "de"
        case .Espanol:
            return "es"
        case .Italiano:
            return "it"
        case .Hrvatski:
            return "hr"
        case .Portuguese:
            return "pt"
        }
    }
        
    static var current: SettingsLanguage {
        get {
            if let langString = UserDefaults.standard.string(forKey: "lang"),
               let lang = SettingsLanguage(rawValue: langString) {
                return lang
            } else {
                return .English
            }
        }
        set {
            // Set the language only for the UI purpose
            UserDefaults.standard.set(newValue.rawValue, forKey: "lang")
            
            // Set the language for the system, must restart the app to have effect
            let languageCode = newValue.appleLanguageCode()
            UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }
    }
}

enum SettingsCurrency: String, CaseIterable {
    case USD
    case AUD
    case EUR
    case GBP
    case CHF
    case JPY
    case CNY
    case CAD
    case SGD
    case SEK
    
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
    
    var usesEuropeanFormat: Bool {
        switch self {
        case .EUR, .CHF:
            return true
        default:
            return false
        }
    }
}

class SettingsOptionsStore {
    static let FAQData : [(question: String, answer: String)] = [
        (question: "setupVaultFAQQuestion", answer: "setupVaultFAQAnswer"),
        (question: "supportedCryptoFAQQuestion", answer: "supportedCryptoFAQAnswer"),
        (question: "vaultSecurityFAQQuestion", answer: "vaultSecurityFAQAnswer"),
        (question: "moneyFAQQuestion", answer: "moneyFAQAnswer"),
        (question: "assetRecoveryFAQQuestion", answer: "assetRecoveryFAQAnswer"),
        (question: "registerFAQQuestion", answer: "registerFAQAnswer")
    ]
}
