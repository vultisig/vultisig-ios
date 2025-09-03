//
//  SwapFeatureGate.swift
//  VultisigApp
//
//  Created by Johnny Luo on 3/9/2025.
//

import Foundation
struct SwapFeatureGate {
    static func isOutsideAppStoreDistribution() -> Bool {
        let profilePath = Bundle.main.path(forResource: "embedded", ofType: "provisionprofile")
        return profilePath != nil
    }
    
    static func canSwap() -> Bool {
        let localeCode = Locale.current.region?.identifier
        if localeCode == "GB" || localeCode == "JP" || localeCode == "MY"{
            return false
        }
        return true
    }
}
