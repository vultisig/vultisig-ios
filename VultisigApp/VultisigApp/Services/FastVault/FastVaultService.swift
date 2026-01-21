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

    func get(pubKeyECDSA: String, password: String) async -> Bool {
        do {
            let urlString = "\(endpoint)/get/\(pubKeyECDSA)"

            let pwd = password.data(using: .utf8)?.base64EncodedString()
            guard let pwd else {
                return false
            }
            _ = try await Utils.asyncGetRequest(urlString: urlString, headers: ["x-password": pwd])
            return true
        } catch {
            return false
        }
    }

    func exist(pubKeyECDSA: String) async -> Bool {
        do {
            let urlString = "\(endpoint)/exist/\(pubKeyECDSA)"
            _ = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
            return true
        } catch {
            return false
        }
    }

    func create(
        name: String,
        sessionID: String,
        hexEncryptionKey: String,
        hexChainCode: String,
        encryptionPassword: String,
        email: String,
        lib_type: Int
    ) {
        let localPartyID = Self.localPartyID(sessionID: sessionID)
        let req = VaultCreateRequest(name: name, session_id: sessionID, hex_encryption_key: hexEncryptionKey, hex_chain_code: hexChainCode, local_party_id: localPartyID, encryption_password: encryptionPassword, email: email, lib_type: lib_type)

        Utils.sendRequest(urlString: "\(endpoint)/create", method: "POST", headers: [:], body: req) { _ in
            print("Send create request to Vultiserver successfully")
        }
    }

    func keyImport(
        name: String,
        sessionID: String,
        hexEncryptionKey: String,
        hexChainCode: String,
        encryptionPassword: String,
        email: String,
        lib_type: Int,
        chains: [String]
    ) {
        let localPartyID = Self.localPartyID(sessionID: sessionID)
        let req = KeyImportRequest(name: name, session_id: sessionID, hex_encryption_key: hexEncryptionKey, hex_chain_code: hexChainCode, local_party_id: localPartyID, encryption_password: encryptionPassword, email: email, lib_type: lib_type, chains: chains)

        Utils.sendRequest(urlString: "\(endpoint)/import", method: "POST", headers: [:], body: req) { _ in
            print("Send create request to Vultiserver successfully")
        }
    }

    func reshare(
        name: String,
        publicKeyECDSA: String,
        sessionID: String,
        hexEncryptionKey: String,
        hexChainCode: String,
        encryptionPassword: String,
        email: String,
        oldParties: [String],
        oldResharePrefix: String,
        lib_type: Int
    ) {
        let localPartyID = Self.localPartyID(sessionID: sessionID)
        let req = ReshareRequest(name: name,
                                 public_key: publicKeyECDSA,
                                 session_id: sessionID,
                                 hex_encryption_key: hexEncryptionKey,
                                 hex_chain_code: hexChainCode,
                                 local_party_id: localPartyID,
                                 old_parties: oldParties,
                                 encryption_password: encryptionPassword,
                                 email: email,
                                 old_reshare_prefix: oldResharePrefix,
                                 lib_type: lib_type)

        Utils.sendRequest(urlString: "\(endpoint)/reshare", method: "POST", headers: [:], body: req) { _ in
            print("Send reshare request to Vultiserver successfully")
        }
    }

    func sign(
        publicKeyEcdsa: String,
        keysignMessages: [String],
        sessionID: String,
        hexEncryptionKey: String,
        derivePath: String,
        isECDSA: Bool,
        vaultPassword: String,
        chain: String,
        completion: @escaping (Bool) -> Void
    ) {
        let request = KeysignRequest(public_key: publicKeyEcdsa, messages: keysignMessages, session: sessionID, hex_encryption_key: hexEncryptionKey, derive_path: derivePath, is_ecdsa: isECDSA, vault_password: vaultPassword, chain: chain)

        Utils.sendRequest(
            urlString: "\(endpoint)/sign",
            method: "POST",
            headers: [:],
            body: request,
            completion: completion
        )
    }

    func verifyBackupOTP(ecdsaKey: String, OTPCode: String) async -> Bool {
        let parameters = "\(ecdsaKey)/\(OTPCode)"
        let urlString = Endpoint.FastVaultBackupVerification + parameters

        guard let url = URL(string: urlString) else {
            print("Invalid URL string.")
            return false
        }

        do {
            let (_, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }

            if httpResponse.statusCode == 200 {
                return true
            } else {
                return false
            }
        } catch {
            print("Error fetching data: \(error.localizedDescription)")
            return false
        }
    }

    func migrate(
        publicKeyECDSA: String,
        sessionID: String,
        hexEncryptionKey: String,
        encryptionPassword: String,
        email: String) {
        let req = MigrationRequest(public_key: publicKeyECDSA,
                                 session_id: sessionID,
                                 hex_encryption_key: hexEncryptionKey,
                                 encryption_password: encryptionPassword,
                                 email: email)

        Utils.sendRequest(urlString: "\(endpoint)/migrate", method: "POST", headers: [:], body: req) { _ in
            print("Send migration request to Vultiserver successfully")
        }
    }
}
