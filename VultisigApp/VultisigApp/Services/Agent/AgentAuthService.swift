//
//  AgentAuthService.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import Foundation
import OSLog
import WalletCore

final class AgentAuthService {

    static let shared = AgentAuthService()

    private let logger = Logger(subsystem: "com.vultisig", category: "AgentAuthService")
    private let keychainPrefix = "vultisig_agent_auth_"

    /// In-memory token cache
    private var tokens: [String: AgentAuthToken] = [:]

    // MARK: - Public API

    /// Sign in to the agent backend using TSS keysign
    func signIn(vault: Vault, password: String) async throws -> AgentAuthToken {
        #if DEBUG
        print("[AgentAuth] 🔐 signIn starting for vault: \(vault.pubKeyECDSA.prefix(20))...")
        #endif
        let authMessage = try generateAuthMessage(vault: vault)
        #if DEBUG
        print("[AgentAuth] 📝 Auth message generated")
        #endif

        // EIP-191 hash the message
        let messageHash = ethereumSignHash(authMessage)
        #if DEBUG
        print("[AgentAuth] #️⃣ Message hashed")
        #endif

        // Fast vault keysign — runs the full DKLS MPC ceremony
        #if DEBUG
        print("[AgentAuth] ✍️ Starting FastVault keysign ceremony...")
        #endif
        let signature = try await performFastVaultKeysign(
            vault: vault,
            messageHash: messageHash,
            password: password
        )
        #if DEBUG
        print("[AgentAuth] ✅ FastVault keysign succeeded (signature length=\(signature.count))")
        #endif

        // Authenticate with verifier
        #if DEBUG
        print("[AgentAuth] 🌐 Authenticating with verifier...")
        #endif
        let authResponse = try await authenticate(
            publicKey: vault.pubKeyECDSA,
            chainCodeHex: vault.hexChainCode,
            signature: signature,
            message: authMessage
        )
        #if DEBUG
        print("[AgentAuth] 🌐 Authenticated (token present, expiresIn=\(authResponse.data.expiresIn))")
        #endif

        guard !authResponse.data.accessToken.isEmpty else {
            #if DEBUG
            print("[AgentAuth] ❌ Empty token received")
            #endif
            throw AgentAuthError.emptyToken
        }

        let token = buildAuthToken(
            accessToken: authResponse.data.accessToken,
            refreshToken: authResponse.data.refreshToken,
            expiresIn: authResponse.data.expiresIn
        )

        // Cache and persist
        tokens[vault.pubKeyECDSA] = token
        persistToken(vaultPubKey: vault.pubKeyECDSA, token: token)

        #if DEBUG
        print("[AgentAuth] ✅ Agent auth signed in successfully, token expires: \(token.expiresAt)")
        #endif
        logger.info("Agent auth signed in successfully")
        return token
    }

    /// Get a valid cached token, or nil if expired/missing
    func getCachedToken(vaultPubKey: String) -> AgentAuthToken? {
        #if DEBUG
        print("[AgentAuth] 🔍 getCachedToken for: \(vaultPubKey.prefix(20))...")
        #endif
        if let token = tokens[vaultPubKey] {
            if token.token.trimmingCharacters(in: .whitespaces).isEmpty {
                invalidateToken(vaultPubKey: vaultPubKey)
                return nil
            }
            let fiveMinutesFromNow = Date().addingTimeInterval(5 * 60)
            if token.expiresAt < fiveMinutesFromNow {
                return nil
            }
            return token
        }

        // Try loading from Keychain
        if let persisted = loadPersistedToken(vaultPubKey: vaultPubKey) {
            tokens[vaultPubKey] = persisted
            let fiveMinutesFromNow = Date().addingTimeInterval(5 * 60)
            if persisted.expiresAt < fiveMinutesFromNow {
                return nil
            }
            return persisted
        }

        return nil
    }

    /// Refresh token if needed
    func refreshIfNeeded(vaultPubKey: String) async -> AgentAuthToken? {
        let token = tokens[vaultPubKey] ?? loadPersistedToken(vaultPubKey: vaultPubKey)
        guard let token else { return nil }

        let fiveMinutesFromNow = Date().addingTimeInterval(5 * 60)
        if token.expiresAt > fiveMinutesFromNow {
            return token
        }

        guard !token.refreshToken.trimmingCharacters(in: .whitespaces).isEmpty else {
            invalidateToken(vaultPubKey: vaultPubKey)
            return nil
        }

        do {
            let response = try await refreshAuthToken(refreshToken: token.refreshToken)
            let newToken = buildAuthToken(
                accessToken: response.data.accessToken,
                refreshToken: response.data.refreshToken,
                expiresIn: response.data.expiresIn
            )
            tokens[vaultPubKey] = newToken
            persistToken(vaultPubKey: vaultPubKey, token: newToken)
            return newToken
        } catch {
            logger.error("Token refresh failed: \(error.localizedDescription)")
            invalidateToken(vaultPubKey: vaultPubKey)
            return nil
        }
    }

    /// Validate the current token with the verifier
    func validate(vaultPubKey: String) async -> Bool {
        guard let token = getCachedToken(vaultPubKey: vaultPubKey) else { return false }

        do {
            try await validateTokenWithVerifier(accessToken: token.token)
            return true
        } catch {
            invalidateToken(vaultPubKey: vaultPubKey)
            return false
        }
    }

    /// Disconnect and revoke all tokens
    func disconnect(vaultPubKey: String) async {
        if let token = getCachedToken(vaultPubKey: vaultPubKey) {
            try? await revokeAllTokens(accessToken: token.token)
        }
        invalidateToken(vaultPubKey: vaultPubKey)
    }

    func isSignedIn(vaultPubKey: String) -> Bool {
        getCachedToken(vaultPubKey: vaultPubKey) != nil
    }

    func invalidateToken(vaultPubKey: String) {
        tokens.removeValue(forKey: vaultPubKey)
        deletePersistedToken(vaultPubKey: vaultPubKey)
    }

    // MARK: - EIP-191 Signing (keccak256 — matching Windows ethereumSigning.ts)

    private func ethereumSignHash(_ message: String) -> String {
        // EIP-191: "\x19Ethereum Signed Message:\n" + len + message, then keccak256
        let prefixed = "\u{19}Ethereum Signed Message:\n\(message.count)\(message)"
        let prefixedData = Data(prefixed.utf8)
        let hash = prefixedData.sha3(.keccak256)
        let hex = hash.hexString
        #if DEBUG
        print("[AgentAuth] #️⃣ EIP-191 keccak256 hash computed (input len=\(message.count))")
        #endif
        return hex
    }

    private func generateAuthMessage(vault: Vault) throws -> String {
        let address = deriveEthereumAddress(vault: vault)
        let expiresAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(15 * 60))

        let message: [String: Any] = [
            "message": "Sign into Vultisig Plugin Marketplace",
            "nonce": generateNonce(),
            "expiresAt": expiresAt,
            "address": address
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys]),
              let jsonString = String(data: data, encoding: .utf8) else {
            throw AgentAuthError.authFailed
        }
        return jsonString
    }

    /// Derive Ethereum address from vault's ECDSA public key using WalletCore HD derivation
    private func deriveEthereumAddress(vault: Vault) -> String {
        // Derive the chain-specific public key using HD key derivation (same as CoinFactory)
        let derivedPubKeyHex = PublicKeyHelper.getDerivedPubKey(
            hexPubKey: vault.pubKeyECDSA,
            hexChainCode: vault.hexChainCode,
            derivePath: CoinType.ethereum.derivationPath()
        )

        guard let pubKeyData = Data(hexString: derivedPubKeyHex),
              let publicKey = WalletCore.PublicKey(data: pubKeyData, type: .secp256k1) else {
            #if DEBUG
            print("[AgentAuth] ⚠️ Failed to derive ETH address via WalletCore")
            #endif
            return ""
        }

        let address = CoinType.ethereum.deriveAddressFromPublicKey(publicKey: publicKey)
        #if DEBUG
        print("[AgentAuth] 📍 Derived ETH address: \(address)")
        #endif
        return address
    }

    private func generateNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return "0x" + bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Fast Vault Keysign (delegates to shared FastVaultKeysignService)

    /// Uses the shared `FastVaultKeysignService` to perform the full MPC ceremony.
    /// Formats the signature as "0x" + r + s + recoveryID (matching Windows' `formatKeysignSignatureHex`).
    private func performFastVaultKeysign(vault: Vault, messageHash: String, password: String) async throws -> String {
        let input = FastVaultKeysignInput(
            vault: vault,
            keysignMessages: [messageHash],
            derivePath: CoinType.ethereum.derivationPath(),
            isECDSA: true,
            vaultPassword: password,
            chain: "Ethereum"
        )

        #if DEBUG
        print("[AgentAuth] ✍️ Delegating keysign to FastVaultKeysignService")
        #endif
        let result = try await FastVaultKeysignService.shared.keysign(input: input)

        // Extract signature for the message hash
        guard let keysignResponse = result.signatures[messageHash] else {
            #if DEBUG
            print("[AgentAuth] ❌ No signature found for message hash in keysign result")
            #endif
            throw AgentAuthError.keysignFailed
        }

        // Format as "0x" + r + s + recoveryID (matching Windows formatKeysignSignatureHex)
        let signature = "0x" + keysignResponse.r + keysignResponse.s + keysignResponse.recoveryID
        #if DEBUG
        print("[AgentAuth] ✅ Signature formatted (length=\(signature.count))")
        #endif
        return signature
    }

    // MARK: - Verifier API Calls

    private func authenticate(publicKey: String, chainCodeHex: String, signature: String, message: String) async throws -> AgentAuthResponse {
        let url = URL(string: Endpoint.verifierAuth())!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "public_key": publicKey,
            "chain_code_hex": chainCodeHex,
            "signature": signature,
            "message": message
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentAuthError.authFailed
        }

        if httpResponse.statusCode != 200 {
            let responseBody = String(data: data, encoding: .utf8) ?? "n/a"
            #if DEBUG
            print("[AgentAuth] ❌ Verifier returned \(httpResponse.statusCode): \(responseBody)")
            #endif
            throw AgentAuthError.authFailed
        }

        do {
            return try JSONDecoder().decode(AgentAuthResponse.self, from: data)
        } catch {
            #if DEBUG
            print("[AgentAuth] ❌ Decoding failed: \(error)")
            #endif
            throw AgentAuthError.authFailed
        }
    }

    private func refreshAuthToken(refreshToken: String) async throws -> AgentAuthResponse {
        let url = URL(string: Endpoint.verifierAuthRefresh())!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AgentAuthError.refreshFailed
        }

        return try JSONDecoder().decode(AgentAuthResponse.self, from: data)
    }

    private func validateTokenWithVerifier(accessToken: String) async throws {
        let url = URL(string: Endpoint.verifierAuthMe())!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AgentAuthError.validationFailed
        }
    }

    private func revokeAllTokens(accessToken: String) async throws {
        let url = URL(string: Endpoint.verifierAuthRevokeAll())!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try await URLSession.shared.data(for: request)
    }

    // MARK: - Token Building

    private func buildAuthToken(accessToken: String, refreshToken: String, expiresIn: Int) -> AgentAuthToken {
        let expiresAt: Date
        if expiresIn > 0 {
            expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        } else {
            // Parse JWT expiry
            expiresAt = parseJwtExpiry(token: accessToken) ?? Date().addingTimeInterval(3600)
        }

        return AgentAuthToken(token: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    private func parseJwtExpiry(token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }

        var payload = String(parts[1])
        let remainder = payload.count % 4
        if remainder == 2 { payload += "==" } else if remainder == 3 { payload += "=" }

        let base64 = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else {
            return nil
        }

        return Date(timeIntervalSince1970: exp)
    }

    // MARK: - Keychain Persistence

    private func persistToken(vaultPubKey: String, token: AgentAuthToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        let key = keychainPrefix + vaultPubKey

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            #if DEBUG
            print("[AgentAuth] ❌ Failed to persist token in Keychain. OSStatus: \(status)")
            #endif
        }
    }

    private func loadPersistedToken(vaultPubKey: String) -> AgentAuthToken? {
        let key = keychainPrefix + vaultPubKey

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AgentAuthToken.self, from: data)
    }

    private func deletePersistedToken(vaultPubKey: String) {
        let key = keychainPrefix + vaultPubKey

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum AgentAuthError: Error, LocalizedError {
    case emptyToken
    case keysignFailed
    case authFailed
    case refreshFailed
    case validationFailed

    var errorDescription: String? {
        switch self {
        case .emptyToken: return "Authentication returned an empty token"
        case .keysignFailed: return "Fast vault keysign failed"
        case .authFailed: return "Authentication failed"
        case .refreshFailed: return "Token refresh failed"
        case .validationFailed: return "Token validation failed"
        }
    }
}
