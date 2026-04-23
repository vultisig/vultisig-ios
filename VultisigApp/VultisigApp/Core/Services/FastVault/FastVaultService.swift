//
//  FastVaultService.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 10.09.2024.
//

import Foundation
import OSLog

/// TargetType for the async FastVault endpoints. Fire-and-forget POSTs
/// (create, keyImport, reshare, singleKeygen, migrate) still use
/// `Utils.sendRequest` — they'll migrate with the Utils network helpers in
/// a later sub-issue of Architecture 3.
enum FastVaultAPI: TargetType {
    /// GET /vault/get/{pubKeyECDSA} with x-password header.
    /// Caller interprets 200 / 401 / 403 / 404 — use .noValidation.
    case get(pubKeyECDSA: String, password: String)
    /// GET /vault/exist/{pubKeyECDSA}.
    case exist(pubKeyECDSA: String)
    /// POST /vault/sign with KeysignRequest body.
    case sign(request: KeysignRequest)
    /// GET /vault/verify/{ecdsaKey}/{otpCode}.
    /// Caller interprets 200 vs anything-else — use .noValidation.
    case verifyBackupOTP(ecdsaKey: String, otpCode: String)

    var baseURL: URL { URL(string: Endpoint.vultisigApiProxy)! }

    var path: String {
        switch self {
        case .get(let pubKey, _):
            return "/vault/get/\(pubKey)"
        case .exist(let pubKey):
            return "/vault/exist/\(pubKey)"
        case .sign:
            return "/vault/sign"
        case .verifyBackupOTP(let key, let otp):
            return "/vault/verify/\(key)/\(otp)"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .get, .exist, .verifyBackupOTP:
            return .get
        case .sign:
            return .post
        }
    }

    var task: HTTPTask {
        switch self {
        case .get, .exist, .verifyBackupOTP:
            return .requestPlain
        case .sign(let request):
            return .requestCodable(request, .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        var base: [String: String] = ["Content-Type": "application/json"]
        if case .get(_, let password) = self,
           let pwd = password.data(using: .utf8)?.base64EncodedString() {
            base["x-password"] = pwd
        }
        return base
    }

    var validationType: ValidationType {
        switch self {
        case .get, .verifyBackupOTP:
            return .noValidation
        case .exist, .sign:
            return .successCodes
        }
    }
}

final class FastVaultService {

    static let shared = FastVaultService()

    private let endpoint = "https://api.vultisig.com/vault"
    private let logger = Logger(subsystem: "com.vultisig", category: "FastVaultService")
    private let httpClient: HTTPClientProtocol

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
        guard password.data(using: .utf8)?.base64EncodedString() != nil else {
            return .networkFailure("Failed to encode FastVault password")
        }

        do {
            let response = try await httpClient.request(
                FastVaultAPI.get(pubKeyECDSA: pubKeyECDSA, password: password)
            )
            let responseBody = String(data: response.data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            switch response.response.statusCode {
            case 200 ... 299:
                return .valid
            case 401, 403:
                return .invalidPassword
            case 404:
                return .vaultNotFound
            default:
                return .requestFailed(
                    statusCode: response.response.statusCode,
                    responseBody: responseBody
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
            _ = try await httpClient.request(FastVaultAPI.exist(pubKeyECDSA: pubKeyECDSA))
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

        do {
            _ = try await httpClient.request(FastVaultAPI.sign(request: request))
        } catch HTTPError.statusCode(let code, let data) {
            let responseBody = data.flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw FastVaultServiceError.signFailed(statusCode: code, responseBody: responseBody)
        } catch {
            throw FastVaultServiceError.invalidResponse
        }
    }

    func verifyBackupOTP(ecdsaKey: String, OTPCode: String) async -> Bool {
        do {
            let response = try await httpClient.request(
                FastVaultAPI.verifyBackupOTP(ecdsaKey: ecdsaKey, otpCode: OTPCode)
            )
            return response.response.statusCode == 200
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

enum FastVaultAccessValidationResult {
    case valid
    case invalidPassword
    case vaultNotFound
    case requestFailed(statusCode: Int, responseBody: String?)
    case networkFailure(String)
}
