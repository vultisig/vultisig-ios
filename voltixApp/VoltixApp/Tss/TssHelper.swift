//
//  TssHelper.swift
//  VoltixApp
//
//  Created by Johnny Luo on 14/4/2024.
//

import Foundation

class TssHelper {
    static func getKeysignRequestHeader(pubKey: String)->[String:String] {
        var header = [String:String]()
        if VoltixRelay.IsRelayEnabled {
            let basicAuthentication = "\(VoltixRelay.VoltixApiKey):\(pubKey)".data(using: .utf8)!
            header["Authorization"] = "Basic \(basicAuthentication.base64EncodedString())"
        }
        return header
    }
    
    static func getKeygenRequestHeader()->[String:String] {
        var header = [String:String]()
        if VoltixRelay.IsRelayEnabled {
            header["keygen"] = "voltix"
            let basicAuthentication = "x:x".data(using: .utf8)!
            header["Authorization"] = "Basic \(basicAuthentication.base64EncodedString())"
        }
        return header
    }
}
