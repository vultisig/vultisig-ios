//
//  SettingsOptionsStore.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import Foundation

enum SettingsLanguage: String {
    case English
    case Deutsch
    case Espanol
    case Italiano
    case Hrvatski
    
    private func description() -> String {
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
