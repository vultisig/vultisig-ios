//
//  FastVaultService.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 10.09.2024.
//

import Foundation
import OSLog

/// Request body for `POST /vault/batch/keygen`.
struct BatchKeygenRequest: Codable {
    let name: String
    let session_id: String
    let hex_encryption_key: String
    let hex_chain_code: String
    let local_party_id: String
    let encryption_password: String
    let email: String
    let lib_type: Int
    let protocols: [String]

    static let protocolECDSA = "ecdsa"
    static let protocolEdDSA = "eddsa"
}

/// Request body for `POST /vault/batch/reshare`.
struct BatchReshareRequest: Codable {
    let public_key: String
    let session_id: String
    let hex_encryption_key: String
    let local_party_id: String
    let old_parties: [String]
    let encryption_password: String
    let email: String
    let protocols: [String]
}

/// Request body for `POST /vault/batch/import`.
struct BatchKeyImportRequest: Codable {
    let name: String
    let session_id: String
    let hex_encryption_key: String
    let local_party_id: String
    let encryption_password: String
    let email: String
    let lib_type: Int
    let chains: [String]
    let protocols: [String]
}

final class FastVaultService {

    static let shared = FastVaultService()

    private let httpClient: HTTPClientProtocol
    private let logger = Logger(subsystem: "com.vultisig.app", category: "fast-vault-service")

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    static func localPartyID(sessionID: String) -> String {
        guard let data = sessionID.data(using: .utf8) else {
            return .empty
        }

        let hash = String(data.hashValue).suffix(5)
        return "Server-\(hash)"
    }

    func validateAccess(pubKeyECDSA: String, password: String) async -> FastVaultAccessValidationResult {
        guard let encodedPassword = password.data(using: .utf8)?.base64EncodedString() else {
            return .networkFailure("Failed to encode FastVault password")
        }

        do {
            let response = try await httpClient.request(
                FastVaultAPI.validateAccess(pubKeyECDSA: pubKeyECDSA, base64Password: encodedPassword)
            )
            let body = String(data: response.data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            switch response.response.statusCode {
            case 200...299:
                return .valid
            case 401, 403:
                return .invalidPassword
            case 404:
                return .vaultNotFound
            default:
                return .requestFailed(
                    statusCode: response.response.statusCode,
                    responseBody: body
                )
            }
        } catch {
            return .networkFailure(error.localizedDescription)
        }
    }

    func get(pubKeyECDSA: String, password: String) async -> Bool {
        let result = await validateAccess(pubKeyECDSA: pubKeyECDSA, password: password)
        if case .valid = result {
            return true
        }
        return false
    }

    func exist(pubKeyECDSA: String) async -> Bool {
        do {
            _ = try await httpClient.request(FastVaultAPI.exists(pubKeyECDSA: pubKeyECDSA))
            return true
        } catch {
            logger.info("FastVault exist check returned false: \(error.localizedDescription, privacy: .public)")
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
    ) async throws {
        let localPartyID = Self.localPartyID(sessionID: sessionID)
        let req = VaultCreateRequest(
            name: name,
            session_id: sessionID,
            hex_encryption_key: hexEncryptionKey,
            hex_chain_code: hexChainCode,
            local_party_id: localPartyID,
            encryption_password: encryptionPassword,
            email: email,
            lib_type: lib_type
        )
        try await send(.create(req), operation: "create")
    }

    func batchCreate(
        name: String,
        sessionID: String,
        hexEncryptionKey: String,
        hexChainCode: String,
        encryptionPassword: String,
        email: String,
        lib_type: Int,
        protocols: [String]
    ) async throws {
        let localPartyID = Self.localPartyID(sessionID: sessionID)
        let req = BatchKeygenRequest(
            name: name,
            session_id: sessionID,
            hex_encryption_key: hexEncryptionKey,
            hex_chain_code: hexChainCode,
            local_party_id: localPartyID,
            encryption_password: encryptionPassword,
            email: email,
            lib_type: lib_type,
            protocols: protocols
        )
        try await send(.batchCreate(req), operation: "batch keygen")
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
    ) async throws {
        let localPartyID = Self.localPartyID(sessionID: sessionID)
        let req = KeyImportRequest(
            name: name,
            session_id: sessionID,
            hex_encryption_key: hexEncryptionKey,
            hex_chain_code: hexChainCode,
            local_party_id: localPartyID,
            encryption_password: encryptionPassword,
            email: email,
            lib_type: lib_type,
            chains: chains
        )
        try await send(.keyImport(req), operation: "import")
    }

    func batchKeyImport(
        name: String,
        sessionID: String,
        hexEncryptionKey: String,
        encryptionPassword: String,
        email: String,
        lib_type: Int,
        chains: [String],
        protocols: [String]
    ) async throws {
        let localPartyID = Self.localPartyID(sessionID: sessionID)
        let req = BatchKeyImportRequest(
            name: name,
            session_id: sessionID,
            hex_encryption_key: hexEncryptionKey,
            local_party_id: localPartyID,
            encryption_password: encryptionPassword,
            email: email,
            lib_type: lib_type,
            chains: chains,
            protocols: protocols
        )
        try await send(.batchKeyImport(req), operation: "batch import")
    }

    func batchReshare(
        publicKeyECDSA: String,
        sessionID: String,
        hexEncryptionKey: String,
        encryptionPassword: String,
        email: String,
        oldParties: [String],
        protocols: [String]
    ) async throws {
        let localPartyID = Self.localPartyID(sessionID: sessionID)
        let req = BatchReshareRequest(
            public_key: publicKeyECDSA,
            session_id: sessionID,
            hex_encryption_key: hexEncryptionKey,
            local_party_id: localPartyID,
            old_parties: oldParties,
            encryption_password: encryptionPassword,
            email: email,
            protocols: protocols
        )
        try await send(.batchReshare(req), operation: "batch reshare")
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
    ) async throws {
        let localPartyID = Self.localPartyID(sessionID: sessionID)
        let req = ReshareRequest(
            name: name,
            public_key: publicKeyECDSA,
            session_id: sessionID,
            hex_encryption_key: hexEncryptionKey,
            hex_chain_code: hexChainCode,
            local_party_id: localPartyID,
            old_parties: oldParties,
            encryption_password: encryptionPassword,
            email: email,
            old_reshare_prefix: oldResharePrefix,
            lib_type: lib_type
        )
        try await send(.reshare(req), operation: "reshare")
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
        isMldsa: Bool = false
    ) async throws {
        let request = KeysignRequest(
            public_key: publicKeyEcdsa,
            messages: keysignMessages,
            session: sessionID,
            hex_encryption_key: hexEncryptionKey,
            derive_path: derivePath,
            is_ecdsa: isECDSA,
            vault_password: vaultPassword,
            chain: chain,
            mldsa: isMldsa
        )
        do {
            _ = try await httpClient.request(FastVaultAPI.sign(request))
        } catch let HTTPError.statusCode(code, data) {
            let body = data.flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw FastVaultServiceError.signFailed(statusCode: code, responseBody: body)
        } catch {
            throw FastVaultServiceError.networkFailure(error)
        }
    }

    func verifyBackupOTP(ecdsaKey: String, OTPCode: String) async -> Bool {
        do {
            _ = try await httpClient.request(
                FastVaultAPI.verifyBackupOTP(pubKeyECDSA: ecdsaKey, code: OTPCode)
            )
            return true
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
    ) async throws {
        let req = CreateMldsaRequest(
            public_key: publicKeyECDSA,
            session_id: sessionID,
            hex_encryption_key: hexEncryptionKey,
            encryption_password: encryptionPassword,
            email: email
        )
        try await send(.singleKeygen(req), operation: "mldsa keygen")
    }

    func migrate(
        publicKeyECDSA: String,
        sessionID: String,
        hexEncryptionKey: String,
        encryptionPassword: String,
        email: String
    ) async throws {
        let req = MigrationRequest(
            public_key: publicKeyECDSA,
            session_id: sessionID,
            hex_encryption_key: hexEncryptionKey,
            encryption_password: encryptionPassword,
            email: email
        )
        try await send(.migrate(req), operation: "migrate")
    }
}

private extension FastVaultService {
    func send(_ target: FastVaultAPI, operation: String) async throws {
        do {
            _ = try await httpClient.request(target)
            logger.info("FastVault \(operation, privacy: .public) request succeeded")
        } catch let HTTPError.statusCode(code, data) {
            let body = data.flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            logger.error("FastVault \(operation, privacy: .public) failed: HTTP \(code) \(body ?? "", privacy: .public)")
            throw FastVaultServiceError.registrationFailed(
                operation: operation,
                statusCode: code,
                responseBody: body
            )
        } catch {
            logger.error("FastVault \(operation, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw FastVaultServiceError.networkFailure(error)
        }
    }
}

enum FastVaultServiceError: Error, LocalizedError {
    case missingEncryptionKey
    case signFailed(statusCode: Int, responseBody: String?)
    case registrationFailed(operation: String, statusCode: Int, responseBody: String?)
    case networkFailure(Error)

    var errorDescription: String? {
        switch self {
        case .missingEncryptionKey:
            return "FastVault encryption key is missing"
        case .signFailed(let statusCode, let responseBody):
            return "FastVault sign failed with status \(statusCode): \(describeBody(responseBody))"
        case .registrationFailed(let operation, let statusCode, let responseBody):
            return "FastVault \(operation) failed with status \(statusCode): \(describeBody(responseBody))"
        case .networkFailure(let error):
            return "FastVault network error: \(error.localizedDescription)"
        }
    }

    private func describeBody(_ body: String?) -> String {
        guard let body, !body.isEmpty else {
            return "empty response body"
        }
        return body
    }
}

enum FastVaultAccessValidationResult {
    case valid
    case invalidPassword
    case vaultNotFound
    case requestFailed(statusCode: Int, responseBody: String?)
    case networkFailure(String)
}
