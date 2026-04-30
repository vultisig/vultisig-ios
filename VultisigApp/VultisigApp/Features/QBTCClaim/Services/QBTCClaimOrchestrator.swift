//
//  QBTCClaimOrchestrator.swift
//  VultisigApp
//
//  Drives the QBTC claim flow as an inline state machine on a single
//  screen: BTC ECDSA round → proof generation → MLDSA round → broadcast.
//  Per the spec design (Option B), each MPC round is delegated to the
//  headless TSS drivers (`DKLSKeysign`, `DilithiumKeysign`) — NOT to
//  `KeysignView` / `KeysignViewModel`. v1 supports FastVault only;
//  SecureVault is deferred to v2.
//

import Foundation
import OSLog

// MARK: - Round runner protocol (production + test seam)

/// Inputs the orchestrator hands to the BTC ECDSA round runner.
struct QBTCClaimBtcRoundInput {
    let vault: Vault
    let btcCoin: Coin
    let messageHashHex: String
    let fastVaultPassword: String
}

/// Inputs the orchestrator hands to the MLDSA round runner.
struct QBTCClaimMldsaRoundInput {
    let vault: Vault
    let qbtcCoin: Coin
    let signDocHashHex: String
    let fastVaultPassword: String
}

/// Result of the BTC round — `(r, s)` extracted from the TSS signature
/// in hex, ready for the proof service's zero-padding step.
struct QBTCClaimBtcRoundResult: Equatable {
    let rHex: String
    let sHex: String
}

// MARK: - Orchestrator

@MainActor
final class QBTCClaimOrchestrator: ObservableObject {
    @Published private(set) var phase: QBTCClaimPhase = .idle

    // Closure-shaped DI for testability. The production initializer
    // wires real services; tests inject mocks.
    typealias GenerateProof = (ClaimProofRequest) async throws -> ClaimProofResponse
    typealias FetchAccountInfo = (String) async throws -> QBTCClaimAccountInfo
    typealias BroadcastClaim = (Data, String) async throws -> String
    typealias RunBtcRound = (QBTCClaimBtcRoundInput) async throws -> QBTCClaimBtcRoundResult
    typealias RunMldsaRound = (QBTCClaimMldsaRoundInput) async throws -> Data
    /// Pushes the round-2 prep message between rounds. No-op for
    /// FastVault (Vultiserver doesn't need a separate prep message —
    /// it's already aware of both rounds via two `signWithServer` POSTs).
    /// SecureVault implementation publishes the prep via the relay's
    /// message channel for the peer device to pick up.
    typealias PushRound2Prep = (QBTCClaimRound2Prep) async throws -> Void

    private let generateProof: GenerateProof
    private let fetchAccountInfo: FetchAccountInfo
    private let broadcastClaim: BroadcastClaim
    private let runBtcRound: RunBtcRound
    private let runMldsaRound: RunMldsaRound
    private let pushRound2Prep: PushRound2Prep

    private let logger = Logger(subsystem: "com.vultisig.app", category: "qbtc-claim")

    init(
        generateProof: @escaping GenerateProof,
        fetchAccountInfo: @escaping FetchAccountInfo,
        broadcastClaim: @escaping BroadcastClaim,
        runBtcRound: @escaping RunBtcRound,
        runMldsaRound: @escaping RunMldsaRound,
        pushRound2Prep: @escaping PushRound2Prep = { _ in }
    ) {
        self.generateProof = generateProof
        self.fetchAccountInfo = fetchAccountInfo
        self.broadcastClaim = broadcastClaim
        self.runBtcRound = runBtcRound
        self.runMldsaRound = runMldsaRound
        self.pushRound2Prep = pushRound2Prep
    }

    /// Resets to `.idle`. Call when the user dismisses an error and
    /// returns to UTXO selection.
    func reset() {
        phase = .idle
    }

    /// Drives the full claim flow. Mutates `phase` as it progresses.
    /// On any error transitions to `.failed(message)` and returns;
    /// the screen is responsible for letting the user retry.
    func run(_ input: QBTCClaimRunInput) async {
        do {
            try await runInternal(input)
        } catch is CancellationError {
            logger.info("Claim run cancelled")
            phase = .failed("qbtcClaimCancelled".localized)
        } catch {
            logger.error("Claim failed: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Internal run

    private func runInternal(_ input: QBTCClaimRunInput) async throws {
        guard let compressedPubkey = Data(hexString: input.btcCoin.hexPublicKey) else {
            throw QBTCClaimOrchestratorError.invalidBtcPublicKey
        }

        // Compute the domain-separated hashes (§2). Cheap; fail fast on
        // schnorr / wrong-length pubkey before we touch the network.
        let hashes = try QBTCClaimHashes.computeAll(
            btcAddress: input.btcCoin.address,
            compressedPubkey: compressedPubkey,
            qbtcAddress: input.qbtcCoin.address,
            chainId: QBTCClaimConfig.chainId
        )
        let messageHashHex = hashes.messageHash.toHexString()

        // Round 1 — BTC ECDSA.
        phase = .signingBTC
        try Task.checkCancellation()
        let btcSig = try await runBtcRound(
            QBTCClaimBtcRoundInput(
                vault: input.vault,
                btcCoin: input.btcCoin,
                messageHashHex: messageHashHex,
                fastVaultPassword: input.fastVaultPassword
            )
        )

        // Proof generation (5-min budget). Account info is fetched
        // AFTER the proof returns: `sequence` and the latest-block
        // timeout fields would go stale if we paralleled them with the
        // multi-minute proof call, leading to broadcast-time
        // sequence/timeout mismatches.
        phase = .generatingProof
        try Task.checkCancellation()
        let proof = try await generateProof(
            ClaimProofRequest(
                rHex: btcSig.rHex,
                sHex: btcSig.sHex,
                compressedPubkeyHex: input.btcCoin.hexPublicKey,
                utxos: input.utxos,
                claimerAddress: input.qbtcCoin.address,
                chainId: QBTCClaimConfig.chainId
            )
        )

        // Treat the proof service's hash echoes as advisory only — the
        // local hashes computed above are the source of truth for the
        // on-chain message. Any mismatch means the service tampered
        // with (or recomputed) the metadata and we must fail before
        // signing or broadcasting.
        let addressHashHex = hashes.addressHash.toHexString()
        let qbtcAddressHashHex = hashes.qbtcAddressHash.toHexString()
        guard proof.messageHash.lowercased() == messageHashHex.lowercased(),
              proof.addressHash.lowercased() == addressHashHex.lowercased(),
              proof.qbtcAddressHash.lowercased() == qbtcAddressHashHex.lowercased() else {
            throw QBTCClaimOrchestratorError.proofHashMismatch
        }

        try Task.checkCancellation()
        let accountInfo = try await fetchAccountInfo(input.qbtcCoin.address)

        // Build the cosmos artifacts for the MLDSA round.
        let claimMessage = QBTCClaimMessage(
            claimer: input.qbtcCoin.address,
            utxos: input.utxos,
            proofHex: proof.proof,
            messageHashHex: messageHashHex,
            addressHashHex: addressHashHex,
            qbtcAddressHashHex: qbtcAddressHashHex
        )
        let bodyBytes = try QBTCHelper.buildClaimTxBody(claimMessage)
        guard let mldsaPubKey = Data(hexString: input.qbtcCoin.hexPublicKey) else {
            throw QBTCClaimOrchestratorError.invalidMldsaPublicKey
        }
        let signDoc = QBTCHelper.buildClaimSignDoc(
            bodyBytes: bodyBytes,
            mldsaPublicKey: mldsaPubKey,
            accountNumber: accountInfo.accountNumber,
            sequence: accountInfo.sequence
        )

        // Push the round-2 prep to the peer (SecureVault) — no-op for
        // FastVault. The peer reconstructs the SignDoc independently
        // from this + the round-1 qbtcClaimContext and verifies before
        // signing. See [[v2-secure-vault-design]].
        try await pushRound2Prep(
            QBTCClaimRound2Prep(
                proofHex: proof.proof,
                messageHashHex: messageHashHex,
                addressHashHex: addressHashHex,
                qbtcAddressHashHex: qbtcAddressHashHex,
                accountNumber: accountInfo.accountNumber,
                sequence: accountInfo.sequence
            )
        )

        // Round 2 — MLDSA. NEW MPC session (the round runner is responsible
        // for generating fresh sessionId + encryption key per call).
        phase = .signingMLDSA
        try Task.checkCancellation()
        let mldsaSignature = try await runMldsaRound(
            QBTCClaimMldsaRoundInput(
                vault: input.vault,
                qbtcCoin: input.qbtcCoin,
                signDocHashHex: signDoc.signDocHashHex,
                fastVaultPassword: input.fastVaultPassword
            )
        )

        // Assemble + broadcast. Locally-computed tx hash (uppercase) is
        // returned even on idempotent replay.
        phase = .broadcasting
        try Task.checkCancellation()
        let txRaw = QBTCHelper.assembleClaimTxRaw(
            bodyBytes: bodyBytes,
            authInfoBytes: signDoc.authInfoBytes,
            mldsaSignature: mldsaSignature
        )
        let broadcastedHash = try await broadcastClaim(txRaw.txRawBytes, txRaw.txHashHex)

        let totalSats = input.utxos.reduce(UInt64(0)) { $0 + $1.amount }
        phase = .done(
            QBTCClaimRunResult(
                txHashHex: broadcastedHash.uppercased(),
                totalSatsClaimed: totalSats
            )
        )
    }
}

enum QBTCClaimOrchestratorError: LocalizedError {
    case invalidBtcPublicKey
    case invalidMldsaPublicKey
    case proofHashMismatch

    var errorDescription: String? {
        switch self {
        case .invalidBtcPublicKey:
            return "qbtcClaimErrorInvalidBtcPublicKey".localized
        case .invalidMldsaPublicKey:
            return "qbtcClaimErrorInvalidMldsaPublicKey".localized
        case .proofHashMismatch:
            return "qbtcClaimErrorProofHashMismatch".localized
        }
    }
}
