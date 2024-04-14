//
//  VoltixPremium.swift
//  VoltixApp
//
//  Created by Johnny Luo on 14/4/2024.
//

import Foundation

class VoltixPremium {
    static var IsPremiumEnabled: Bool {
        get {
            return true
        }
    }
    static var VoltixApiKey: String{
        get{
            return UserDefaults.standard.string(forKey: "voltix_apikey") ?? ""
        }
        set{
            UserDefaults.standard.set(newValue, forKey: "voltix_apikey")
        }
    }
}
