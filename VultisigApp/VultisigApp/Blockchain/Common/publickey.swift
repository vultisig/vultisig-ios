//
//  publickey.swift
//  VultisigApp
//

import Foundation
import Tss
import OSLog

enum PublicKeyHelper {
    static func getDerivedPubKey(hexPubKey: String, hexChainCode: String, derivePath: String) -> String {
        var nsErr: NSError?
        let derivedPubKey = TssGetDerivedPubKey(hexPubKey, hexChainCode, derivePath, false, &nsErr)
        if let nsErr {
            Log.chain.other.error("fail to get derived pubkey:\(nsErr.localizedDescription, privacy: .public)")
            return ""
        }
        return derivedPubKey
    }
}
