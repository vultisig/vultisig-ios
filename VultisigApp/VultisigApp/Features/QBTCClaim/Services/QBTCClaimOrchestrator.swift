//
//  QBTCClaimOrchestrator.swift
//  VultisigApp
//
//  Drives the QBTC claim flow as an inline state machine on a single
//  screen.
//
//  Post-qbtc#158 (proof-service service-side broadcast):
//    BTC ECDSA MPC round → POST /prove (broadcast=true) → done.
//
//  The proof service signs `MsgClaimWithProof` with its own MLDSA-44 key
//  and broadcasts it; iOS no longer runs an MLDSA TSS round, builds a
//  cosmos `SignDoc` / `AuthInfo` / `TxRaw`, or hits the Tendermint RPC.
//

import Foundation
import OSLog
import WalletCore

// MARK: - Round runner protocol (production + test seam)

/// Inputs the orchestrator hands to the BTC ECDSA round runner.
struct QBTCClaimBtcRoundInput {
    let vault: Vault
    let btcCoin: Coin
    let messageHashHex: String
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
    typealias RunBtcRound = (QBTCClaimBtcRoundInput) async throws -> QBTCClaimBtcRoundResult

    private let generateProof: GenerateProof
    private let runBtcRound: RunBtcRound

    private let logger = Logger(subsystem: "com.vultisig.app", category: "qbtc-claim")

    init(
        generateProof: @escaping GenerateProof,
        runBtcRound: @escaping RunBtcRound
    ) {
        self.generateProof = generateProof
        self.runBtcRound = runBtcRound
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

        // Round 1 — BTC ECDSA (the only MPC round under post-#158 flow).
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

        // Generate proof + service-side broadcast in one round-trip
        // (qbtc proof-service #158). The service signs `MsgClaimWithProof`
        // with its own MLDSA-44 key, pays the fee, and returns the on-chain
        // tx hash; iOS no longer assembles or broadcasts a cosmos tx.
        // Budget: 5 min — proof generation dominates.
        phase = .generatingProofAndBroadcasting
        try Task.checkCancellation()
        let proof = try await generateProof(
            ClaimProofRequest(
                rHex: btcSig.rHex,
                sHex: btcSig.sHex,
                compressedPubkeyHex: input.btcCoin.hexPublicKey,
                utxos: input.utxos,
                claimerAddress: input.qbtcCoin.address,
                chainId: QBTCClaimConfig.chainId,
                broadcast: true
            )
        )

        // Sanity-check the service's hash echoes against locally-computed
        // values. Drift means the service tampered with (or recomputed) the
        // metadata for a `MsgClaimWithProof` it then broadcast on our
        // behalf — fail loudly even though we no longer build the tx
        // ourselves.
        let addressHashHex = hashes.addressHash.toHexString()
        let qbtcAddressHashHex = hashes.qbtcAddressHash.toHexString()
        guard proof.messageHash.lowercased() == messageHashHex.lowercased(),
              proof.addressHash.lowercased() == addressHashHex.lowercased(),
              proof.qbtcAddressHash.lowercased() == qbtcAddressHashHex.lowercased() else {
            throw QBTCClaimOrchestratorError.proofHashMismatch
        }

        // Service-side broadcast must produce a non-empty tx hash. A nil
        // or empty `txHash` here means the service either rejected the
        // broadcast (BROADCAST_NOT_CONFIGURED, CHAIN_ID_MISMATCH) or the
        // chain rejected the tx (BROADCAST_FAILED). We don't fall back
        // to a client-side build/broadcast — that path is intentionally
        // removed.
        guard let txHash = proof.txHash, !txHash.isEmpty else {
            throw QBTCClaimOrchestratorError.broadcastUnavailable
        }

        let totalSats = input.utxos.reduce(UInt64(0)) { $0 + $1.amount }
        phase = .done(
            QBTCClaimRunResult(
                txHashHex: txHash.uppercased(),
                totalSatsClaimed: totalSats
            )
        )
    }
}

enum QBTCClaimOrchestratorError: LocalizedError {
    case invalidBtcPublicKey
    case proofHashMismatch
    case broadcastUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidBtcPublicKey:
            return "qbtcClaimErrorInvalidBtcPublicKey".localized
        case .proofHashMismatch:
            return "qbtcClaimErrorProofHashMismatch".localized
        case .broadcastUnavailable:
            return "qbtcClaimErrorBroadcastUnavailable".localized
        }
    }
}
