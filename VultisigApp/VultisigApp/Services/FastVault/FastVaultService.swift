//
//  FastVaultService.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 10.09.2024.
//

import Foundation
import OSLog

final class FastVaultService {

    static let shared = FastVaultService()

    private let endpoint = "https://api.vultisig.com/vault"
    private let logger = Logger(subsystem: "com.vultisig", category: "FastVaultService")

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

    /// Determines if a vault is eligible for fast signing
    /// - Parameter vault: The vault to check
    /// - Returns: `true` if the vault exists in the backend, is not a local backup, and is configured as a fast vault
    func isEligibleForFastSign(vault: Vault) async -> Bool {
        let isExist = await exist(pubKeyECDSA: vault.pubKeyECDSA)
        return isExist && vault.isFastVault
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
            self.logger.info("Sent FastVault create request successfully")
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
            self.logger.info("Sent FastVault import request successfully")
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
            self.logger.info("Sent FastVault reshare request successfully")
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
        chain: String
    ) async throws {
        let request = KeysignRequest(public_key: publicKeyEcdsa, messages: keysignMessages, session: sessionID, hex_encryption_key: hexEncryptionKey, derive_path: derivePath, is_ecdsa: isECDSA, vault_password: vaultPassword, chain: chain)
        guard let url = URL(string: "\(endpoint)/sign") else {
            throw FastVaultServiceError.invalidSignURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FastVaultServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw FastVaultServiceError.signFailed(
                statusCode: httpResponse.statusCode,
                responseBody: responseBody
            )
        }
    }

    func verifyBackupOTP(ecdsaKey: String, OTPCode: String) async -> Bool {
        let parameters = "\(ecdsaKey)/\(OTPCode)"
        let urlString = Endpoint.FastVaultBackupVerification + parameters

        guard let url = URL(string: urlString) else {
            logger.error("FastVault backup verification URL is invalid")
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
            logger.error("FastVault backup verification failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func singleKeygen(
        publicKeyECDSA: String,
        sessionID: String,
        hexEncryptionKey: String,
        encryptionPassword: String,
        email: String
    ) {
        let req = CreateMldsaRequest(
            public_key: publicKeyECDSA,
            session_id: sessionID,
            hex_encryption_key: hexEncryptionKey,
            encryption_password: encryptionPassword,
            email: email
        )

        Utils.sendRequest(urlString: "\(endpoint)/mldsa", method: "POST", headers: [:], body: req) { _ in
            self.logger.info("Sent FastVault MLDSA keygen request successfully")
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
            self.logger.info("Sent FastVault migration request successfully")
        }
    }
}

enum FastVaultServiceError: Error, LocalizedError {
    case invalidSignURL
    case invalidResponse
    case signFailed(statusCode: Int, responseBody: String?)

    var errorDescription: String? {
        switch self {
        case .invalidSignURL:
            return "FastVault sign URL is invalid"
        case .invalidResponse:
            return "FastVault sign returned an invalid response"
        case .signFailed(let statusCode, let responseBody):
            let body: String
            if let responseBody, !responseBody.isEmpty {
                body = responseBody
            } else {
                body = "empty response body"
            }
            return "FastVault sign failed with status \(statusCode): \(body)"
        }
    }
}
