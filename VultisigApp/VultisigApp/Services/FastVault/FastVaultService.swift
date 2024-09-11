//
//  FastVaultService.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 10.09.2024.
//

import Foundation

final class FastVaultService {

    static let shared = FastVaultService()

    private let endpoint = "https://api.vultisig.com/vault"

    static func localPartyID(sessionID: String) -> String {
        guard let data = sessionID.data(using: .utf8) else {
            return .empty
        }

        let hash = String(data.hashValue).suffix(5)
        return "Server-\(hash)"
    }

    func create(
        name: String,
        sessionID: String,
        hexEncryptionKey: String,
        hexChainCode: String,
        encryptionPassword: String,
        email: String
    ) {
        let localPartyID = Self.localPartyID(sessionID: sessionID)
        let req = VaultCreateRequest(name: name, session_id: sessionID, hex_encryption_key: hexEncryptionKey, hex_chain_code: hexChainCode, local_party_id: localPartyID, encryption_password: encryptionPassword, email: email)

        Utils.sendRequest(urlString: "\(endpoint)/create", method: "POST", headers: [:], body: req) { _ in
            print("Send create request to vultisigner successfully")
        }
    }

    func reshare(
        name: String,
        publicKeyECDSA: String,
        sessionID: String,
        hexEncryptionKey: String,
        hexChainCode: String,
        encryptionPassword:String,
        email: String
    ) {
        let localPartyID = Self.localPartyID(sessionID: sessionID)
        let req = ReshareRequest(name: name,public_key: publicKeyECDSA, session_id: sessionID, hex_encryption_key: hexEncryptionKey, hex_chain_code: hexChainCode, local_party_id: localPartyID, encryption_password: encryptionPassword, email: email)

        Utils.sendRequest(urlString: "\(endpoint)/reshare", method: "POST", headers: [:], body: req) { _ in
            print("Send reshare request to vultisigner successfully")
        }
    }

    func sign(
        publicKeyEcdsa: String,
        keysignMessages: [String],
        sessionID: String,
        hexEncryptionKey: String,
        derivePath:String,
        isECDSA: Bool,
        vaultPassword: String
    ) {
        let req = KeysignRequest(public_key: publicKeyEcdsa, messages: keysignMessages, session: sessionID, hex_encryption_key: hexEncryptionKey, derive_path: derivePath, is_ecdsa: isECDSA, vault_password: vaultPassword)

        Utils.sendRequest(urlString: "\(endpoint)/sign", method: "POST", headers: [:], body: req) { _ in
            print("Send sign request to vultisigner successfully")
        }
    }
}
