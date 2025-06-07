//
//  ReshareMessage.swift
//  VultisigApp
//
//  Created by Johnny Luo on 14/3/2024.
//

struct ReshareMessage {
    let sessionID: String
    let hexChainCode: String
    let serviceName: String
    let pubKeyECDSA: String
    let oldParties: [String]
    let encryptionKeyHex: String
    let useVultisigRelay: Bool
    let oldResharePrefix: String
    let vaultName: String
    let libType: LibType
}
