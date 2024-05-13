//
//  KeygenMessage.swift
//  VultisigApp
//

struct keygenMessage: Codable {
    let sessionID: String
    let hexChainCode: String
    let serviceName: String
    let encryptionKeyHex: String
    let useVultisigRelay: Bool
    let vaultName: String
}
