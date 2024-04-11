//
//  ReshareMessage.swift
//  VoltixApp
//
//  Created by Johnny Luo on 14/3/2024.
//

struct ReshareMessage: Codable {
    let sessionID: String
    let hexChainCode: String
    let serviceName: String
    let pubKeyECDSA: String
    let oldParties: [String]
    let encryptionKeyHex: String
}
