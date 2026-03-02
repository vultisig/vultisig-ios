//
//  SingleKeygenMessage.swift
//  VultisigApp
//

struct SingleKeygenMessage {
    let sessionID: String
    let hexChainCode: String
    let serviceName: String
    let pubKeyECDSA: String
    let oldParties: [String]
    let encryptionKeyHex: String
    let useVultisigRelay: Bool
    let vaultName: String
    let libType: LibType
    let singleKeygenType: SingleKeygenType
}
