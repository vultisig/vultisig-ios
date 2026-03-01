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

    /// Perform a headless FastVault keysign with retry (mirrors Windows' `fastVaultKeysign()`).
    func keysign(input: FastVaultKeysignInput) async throws -> FastVaultKeysignResult {
        var lastError: Error?

        for attempt in 1...input.maxAttempts {
            do {
                let result = try await keysignAttempt(input: input)
                return result
            } catch {
                lastError = error
                print("[FastVaultKeysign] ⚠️ Attempt \(attempt)/\(input.maxAttempts) failed: \(error.localizedDescription)")
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

        print("[FastVaultKeysign] 🚀 Starting keysign ceremony")
        print("[FastVaultKeysign]   sessionID=\(sessionID)")
        print("[FastVaultKeysign]   localPartyID=\(localPartyID)")
        print("[FastVaultKeysign]   serverAddr=\(serverAddr)")
        print("[FastVaultKeysign]   derivePath=\(input.derivePath)")
        print("[FastVaultKeysign]   isECDSA=\(input.isECDSA)")
        print("[FastVaultKeysign]   chain=\(input.chain)")
        print("[FastVaultKeysign]   messages=\(input.keysignMessages.map { String($0.prefix(20)) })")
        print("[FastVaultKeysign]   signingPublicKey=\(signingPublicKey.prefix(20))...")
        print("[FastVaultKeysign]   vaultIdentifierKey=\(vaultIdentifierKey.prefix(20))...")

        // Step 1: Register session on relay
        try await registerSession(serverAddr: serverAddr, sessionID: sessionID, localPartyID: localPartyID)
        print("[FastVaultKeysign] ✅ Step 1: Session registered on relay")

        // Step 2: Invite VultiServer (uses ECDSA key for vault identification)
        print("[FastVaultKeysign] 📡 Step 2: Inviting VultiServer via FastVaultService.sign()...")
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
        print("[FastVaultKeysign] ✅ Step 2: VultiServer invited")

        // Step 3: Wait for VultiServer to join (poll participants)
        // IMPORTANT: Use ACTUAL discovered parties, not pre-computed IDs (matches Windows)
        print("[FastVaultKeysign] 👥 Step 3: Waiting for peers...")
        let parties = try await waitForParties(serverAddr: serverAddr, sessionID: sessionID, expected: 2)
        print("[FastVaultKeysign] ✅ Step 3: Peers discovered: \(parties)")

        // Use actual discovered parties as the keysign committee (matching Windows)
        // Windows: const peers = parties.filter(p => p !== vault.localPartyId)
        let keysignCommittee = parties
        let actualPeers = parties.filter { $0 != localPartyID }
        print("[FastVaultKeysign] 📋 Keysign committee (from discovered parties): \(keysignCommittee)")
        print("[FastVaultKeysign] 📋 Actual peers: \(actualPeers)")

        // Step 4: Start the session with actual parties
        print("[FastVaultKeysign] 🔄 Step 4: Starting session...")
        try await startSession(serverAddr: serverAddr, sessionID: sessionID, parties: parties)
        print("[FastVaultKeysign] ✅ Step 4: Keysign started")

        // Step 5: Run local keysign (DKLS for ECDSA, Schnorr for EdDSA)
        let chainPath = input.derivePath.replacingOccurrences(of: "'", with: "")
        print("[FastVaultKeysign] ⚙️ Step 5: Starting \(input.isECDSA ? "DKLS (ECDSA)" : "Schnorr (EdDSA)") keysign...")
        print("[FastVaultKeysign]   chainPath=\(chainPath)")
        print("[FastVaultKeysign]   committee=\(keysignCommittee)")
        print("[FastVaultKeysign]   encryptionKeyHex=\(encryptionKeyHex.prefix(8))...")
        print("[FastVaultKeysign]   vault.localPartyID=\(input.vault.localPartyID)")
        print("[FastVaultKeysign]   vault.publicKeys=\(signingPublicKey.prefix(20))...")

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

        print("[FastVaultKeysign] ✅ Step 5: Keysign completed!")

        // Step 6: Return signatures
        print("[FastVaultKeysign] 📝 Step 6: Got \(signatures.count) signature(s)")
        for (hash, sig) in signatures {
            print("[FastVaultKeysign]   hash=\(hash.prefix(20))... key=\(sig.r.prefix(10))...\(sig.s.prefix(10))...")
        }
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
        let success = await withCheckedContinuation { continuation in
            FastVaultService.shared.sign(
                publicKeyEcdsa: publicKey,
                keysignMessages: keysignMessages,
                sessionID: sessionID,
                hexEncryptionKey: encryptionKeyHex,
                derivePath: derivePath,
                isECDSA: isECDSA,
                vaultPassword: vaultPassword,
                chain: chain
            ) { success in
                continuation.resume(returning: success)
            }
        }

        guard success else {
            throw FastVaultKeysignError.keysignFailed("FastVaultService.sign failed")
        }
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
                    print("[FastVaultKeysign] 👥 Waiting for peers: \(parties.count)/\(expected)")
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
