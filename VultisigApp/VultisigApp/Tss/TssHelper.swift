//
//  TssHelper.swift
//  VultisigApp
//
//  Created by Johnny Luo on 14/4/2024.
//

import Foundation

class TssHelper {
    static func getKeysignRequestHeader(pubKey: String)->[String:String] {
        var header = [String:String]()
        if VultisigRelay.IsRelayEnabled {
            let basicAuthentication = "\(VultisigRelay.VultisigApiKey):\(pubKey)".data(using: .utf8)!
            header["Authorization"] = "Basic \(basicAuthentication.base64EncodedString())"
        }
        return header
    }
    
    static func getKeygenRequestHeader()->[String:String] {
        var header = [String:String]()
        if VultisigRelay.IsRelayEnabled {
            header["keygen"] = "Vultisig"
            let basicAuthentication = "x:x".data(using: .utf8)!
            header["Authorization"] = "Basic \(basicAuthentication.base64EncodedString())"
        }
        return header
    }
}
