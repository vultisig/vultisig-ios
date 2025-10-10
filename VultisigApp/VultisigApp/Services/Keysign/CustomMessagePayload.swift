//
//  CustomMessagePayload.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 29.11.2024.
//

import Foundation

struct CustomMessagePayload: Codable, Hashable {
    let method: String
    let message: String
    let vaultPublicKeyECDSA: String
    let vaultLocalPartyID: String
    let chain: String
    
    /// Decoded human-readable version of the message (populated asynchronously)
    var decodedMessage: String? = nil

    var keysignMessages: [String] {
        let data: Data

        if message.starts(with: "0x"){
            data = Data(hex: message)
        }else {
            data = Data(message.utf8)
        }

        let hash = data.sha3(.keccak256)
        return [hash.hexString]
    }
}
