//
//  publickey.swift
//  VoltixApp
//

import Foundation
import Tss

enum PublicKeyHelper {
    static func getDerivedPubKey(hexPubKey: String, hexChainCode: String, derivePath: String) -> String {
        var nsErr: NSError?
        let derivedPubKey = TssGetDerivedPubKey(hexPubKey, hexChainCode, derivePath, false, &nsErr)
        if let nsErr {
            print("fail to get derived pubkey:\(nsErr.localizedDescription)")
            return ""
        }
        return derivedPubKey
    }
}
