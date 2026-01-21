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
    case Chinese
    
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
        case .Chinese:
            return NSLocalizedString("Chinese", comment: "Chinese")
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
        case .Chinese:
            return "zh-Hans"
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

enum SettingsAPRPeriod: String, CaseIterable {
    case oneDay = "1d"
    case oneWeek = "7d"
    case oneMonth = "30d"
    case oneHundredDays = "100d"
    case oneYear = "365d"

    func description() -> String {
        switch self {
        case .oneDay:
            return "apr1Day".localized
        case .oneWeek:
            return "apr1Week".localized
        case .oneMonth:
            return "apr1Month".localized
        case .oneHundredDays:
            return "apr100Days".localized
        case .oneYear:
            return "apr1Year".localized
        }
    }

    static var current: SettingsAPRPeriod {
        get {
            if let periodString = UserDefaults.standard.string(forKey: "aprPeriod"),
               let period = SettingsAPRPeriod(rawValue: periodString) {
                return period
            } else {
                return .oneMonth  // Default to 30d (industry standard)
            }
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "aprPeriod")
        }
    }
}

class SettingsOptionsStore {
    static let FAQData: [(question: String, answer: String)] = Range(1...9).map {
        (question: "faqQuestion\($0)", answer: "faqAnswer\($0)")
    }
}
