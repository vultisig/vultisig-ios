//
//  FastVaultKeysignService.swift
//  VultisigApp
//
//  Headless FastVault keysign orchestrator — mirrors Windows' fastVaultKeysign.ts.
//  Encapsulates the relay session + MPC ceremony so callers don't duplicate code.
//

import Foundation
import OSLog
import Tss
import WalletCore

/// Result of a headless FastVault keysign ceremony.
struct FastVaultKeysignResult {
    let signatures: [String: TssKeysignResponse]
}

/// Input parameters for the FastVault keysign ceremony.
struct FastVaultKeysignInput {
    let vault: Vault
    let keysignMessages: [String]
    let derivePath: String
    let isECDSA: Bool
    let vaultPassword: String
    let chain: String
    /// Maximum number of retry attempts (default 2, matching Windows).
    var maxAttempts: Int = 2
}

/// Shared headless FastVault keysign service.
/// Performs the full 6-step relay + MPC ceremony without any UI dependencies.
///
/// Steps:
/// 1. Register session on relay
/// 2. Invite VultiServer via `FastVaultService.sign()`
/// 3. Poll relay until VultiServer joins
/// 4. Start the keysign session
/// 5. Run local DKLS keysign
/// 6. Return signatures
final class FastVaultKeysignService {

    static let shared = FastVaultKeysignService()

    private let logger = Logger(subsystem: "com.vultisig", category: "FastVaultKeysignService")

    private func debugLog(_ message: String) {
        #if DEBUG
        logger.debug("\(message, privacy: .public)")
        #endif
    }

    private func warningLog(_ message: String) {
        #if DEBUG
        logger.warning("\(message, privacy: .public)")
        #endif
    }

    /// Perform a headless FastVault keysign with retry (mirrors Windows' `fastVaultKeysign()`).
    func keysign(input: FastVaultKeysignInput) async throws -> FastVaultKeysignResult {
        var lastError: Error?

        for attempt in 1...input.maxAttempts {
            do {
                let result = try await keysignAttempt(input: input)
                return result
            } catch {
                lastError = error
                warningLog("[FastVaultKeysign] Attempt \(attempt)/\(input.maxAttempts) failed: \(error.localizedDescription)")
                if attempt < input.maxAttempts && isRetryable(error) {
                    try await Task.sleep(for: .seconds(2))
                    continue
                }
            }
        }

        throw lastError ?? FastVaultKeysignError.keysignFailed("Unknown error")
    }

    // MARK: - Single Attempt

    private func keysignAttempt(input: FastVaultKeysignInput) async throws -> FastVaultKeysignResult {
        let sessionID = UUID().uuidString
        let serverAddr = Endpoint.vultisigRelay
        let localPartyID = input.vault.localPartyID

        // Generate encryption key for relay message encryption
        guard let encryptionKeyHex = Encryption.getEncryptionKey() else {
            throw FastVaultKeysignError.keysignFailed("Failed to generate encryption key")
        }

        // The server ALWAYS identifies vaults by the ECDSA public key.
        // For the MPC ceremony, we use the correct signing key type.
        let signingPublicKey = input.isECDSA ? input.vault.pubKeyECDSA : input.vault.pubKeyEdDSA
        let vaultIdentifierKey = input.vault.pubKeyECDSA  // Always ECDSA for server API

        debugLog("[FastVaultKeysign] Starting keysign ceremony for \(input.chain)")

        // Step 1: Register session on relay
        try await registerSession(serverAddr: serverAddr, sessionID: sessionID, localPartyID: localPartyID)
        debugLog("[FastVaultKeysign] Step 1: Session registered on relay")

        // Step 2: Invite VultiServer (uses ECDSA key for vault identification)
        debugLog("[FastVaultKeysign] Step 2: Inviting VultiServer")
        try await inviteServer(
            publicKey: vaultIdentifierKey,
            keysignMessages: input.keysignMessages,
            sessionID: sessionID,
            encryptionKeyHex: encryptionKeyHex,
            derivePath: input.derivePath,
            isECDSA: input.isECDSA,
            vaultPassword: input.vaultPassword,
            chain: input.chain
        )
        debugLog("[FastVaultKeysign] Step 2: VultiServer invited")

        // Step 3: Wait for VultiServer to join (poll participants)
        // IMPORTANT: Use ACTUAL discovered parties, not pre-computed IDs (matches Windows)
        debugLog("[FastVaultKeysign] Step 3: Waiting for peers")
        let parties = try await waitForParties(serverAddr: serverAddr, sessionID: sessionID, expected: 2)
        debugLog("[FastVaultKeysign] Step 3: Peers discovered: \(parties.count)")

        // Use actual discovered parties as the keysign committee (matching Windows)
        // Windows: const peers = parties.filter(p => p !== vault.localPartyId)
        let keysignCommittee = parties
        let actualPeers = parties.filter { $0 != localPartyID }
        debugLog("[FastVaultKeysign] Step 3: Actual peers discovered: \(actualPeers.count)")

        // Step 4: Start the session with actual parties
        debugLog("[FastVaultKeysign] Step 4: Starting session")
        try await startSession(serverAddr: serverAddr, sessionID: sessionID, parties: parties)
        debugLog("[FastVaultKeysign] Step 4: Keysign started")

        // Step 5: Run local keysign (DKLS for ECDSA, Schnorr for EdDSA)
        let chainPath = input.derivePath.replacingOccurrences(of: "'", with: "")
        debugLog("[FastVaultKeysign] Step 5: Starting \(input.isECDSA ? "DKLS" : "Schnorr") keysign")

        let signatures: [String: TssKeysignResponse]
        if input.isECDSA {
            let dklsKeysign = DKLSKeysign(
                keysignCommittee: keysignCommittee,
                mediatorURL: serverAddr,
                sessionID: sessionID,
                messsageToSign: input.keysignMessages,
                vault: input.vault,
                encryptionKeyHex: encryptionKeyHex,
                chainPath: chainPath,
                isInitiateDevice: true,
                publicKeyECDSA: signingPublicKey
            )
            try await dklsKeysign.DKLSKeysignWithRetry()
            signatures = dklsKeysign.getSignatures()
        } else {
            let schnorrKeysign = SchnorrKeysign(
                keysignCommittee: keysignCommittee,
                mediatorURL: serverAddr,
                sessionID: sessionID,
                messsageToSign: input.keysignMessages,
                vault: input.vault,
                encryptionKeyHex: encryptionKeyHex,
                isInitiateDevice: true,
                publicKeyEdDSA: signingPublicKey
            )
            try await schnorrKeysign.KeysignWithRetry()
            signatures = schnorrKeysign.getSignatures()
        }

        debugLog("[FastVaultKeysign] Step 5: Keysign completed")

        // Step 6: Return signatures
        debugLog("[FastVaultKeysign] Step 6: Produced \(signatures.count) signature(s)")
        guard !signatures.isEmpty else {
            throw FastVaultKeysignError.keysignFailed("No signatures produced")
        }

        return FastVaultKeysignResult(signatures: signatures)
    }

    // MARK: - Relay Helpers (mirrors Windows relayClient.ts)

    /// POST /{sessionID} — register local party on relay
    private func registerSession(serverAddr: String, sessionID: String, localPartyID: String) async throws {
        let urlString = "\(serverAddr)/\(sessionID)"
        let body = [localPartyID]
        let bodyData = try JSONEncoder().encode(body)
        _ = try await Utils.asyncPostRequest(urlString: urlString, headers: nil, body: bodyData)
    }

    /// Call FastVaultService.sign to invite VultiServer
    private func inviteServer(
        publicKey: String,
        keysignMessages: [String],
        sessionID: String,
        encryptionKeyHex: String,
        derivePath: String,
        isECDSA: Bool,
        vaultPassword: String,
        chain: String
    ) async throws {
        try await FastVaultService.shared.sign(
            publicKeyEcdsa: publicKey,
            keysignMessages: keysignMessages,
            sessionID: sessionID,
            hexEncryptionKey: encryptionKeyHex,
            derivePath: derivePath,
            isECDSA: isECDSA,
            vaultPassword: vaultPassword,
            chain: chain
        )
    }

    /// GET /{sessionID} — poll until expected number of parties join (mirrors Windows waitForParties)
    private func waitForParties(serverAddr: String, sessionID: String, expected: Int, timeoutSeconds: TimeInterval = 120) async throws -> [String] {
        let urlString = "\(serverAddr)/\(sessionID)"
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeoutSeconds {
            do {
                let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
                if let parties = try? JSONDecoder().decode([String].self, from: data) {
                    if parties.count >= expected {
                        return parties
                    }
                    debugLog("[FastVaultKeysign] Waiting for peers: \(parties.count)/\(expected)")
                }
            } catch {
                // Ignore polling errors (matches Windows behavior)
            }
            try await Task.sleep(for: .seconds(1))
        }

        throw FastVaultKeysignError.keysignFailed("Timeout waiting for \(expected) parties in session \(sessionID)")
    }

    /// POST /start/{sessionID} — kick off (mirrors Windows startSession)
    private func startSession(serverAddr: String, sessionID: String, parties: [String]) async throws {
        let urlString = "\(serverAddr)/start/\(sessionID)"
        let bodyData = try JSONEncoder().encode(parties)
        _ = try await Utils.asyncPostRequest(urlString: urlString, headers: nil, body: bodyData)
    }

    // MARK: - Retry Logic

    private func isRetryable(_ error: Error) -> Bool {
        let msg = error.localizedDescription.lowercased()
        return msg.contains("timeout") ||
               msg.contains("deadline exceeded") ||
               msg.contains("unreachable") ||
               msg.contains("keysign failed")
    }
}

// MARK: - Errors

enum FastVaultKeysignError: Error, LocalizedError {
    case keysignFailed(String)

    var errorDescription: String? {
        switch self {
        case .keysignFailed(let reason):
            return "FastVault keysign failed: \(reason)"
        }
    }
}
