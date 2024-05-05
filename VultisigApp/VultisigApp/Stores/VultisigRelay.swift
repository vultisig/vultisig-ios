//
//  VultisigRelay.swift
//  VultisigApp
//
//  Created by Johnny Luo on 14/4/2024.
//

import Foundation

class VultisigRelay {
    static var IsRelayEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "use_vultisig_relay")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "use_vultisig_relay")
        }
    }
    static var VultisigApiKey: String{
        get{
            return UserDefaults.standard.string(forKey: "vultisig_apikey") ?? ""
        }
        set{
            UserDefaults.standard.set(newValue, forKey: "vultisig_apikey")
        }
    }
}
