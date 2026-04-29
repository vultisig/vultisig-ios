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

    private let generateProof: GenerateProof
    private let fetchAccountInfo: FetchAccountInfo
    private let broadcastClaim: BroadcastClaim
    private let runBtcRound: RunBtcRound
    private let runMldsaRound: RunMldsaRound

    private let logger = Logger(subsystem: "com.vultisig.app", category: "qbtc-claim")

    init(
        generateProof: @escaping GenerateProof,
        fetchAccountInfo: @escaping FetchAccountInfo,
        broadcastClaim: @escaping BroadcastClaim,
        runBtcRound: @escaping RunBtcRound,
        runMldsaRound: @escaping RunMldsaRound
    ) {
        self.generateProof = generateProof
        self.fetchAccountInfo = fetchAccountInfo
        self.broadcastClaim = broadcastClaim
        self.runBtcRound = runBtcRound
        self.runMldsaRound = runMldsaRound
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
            phase = .failed("Claim cancelled")
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

        // Proof generation (5-min budget). Then fetch account info.
        phase = .generatingProof
        try Task.checkCancellation()
        async let proofTask = generateProof(
            ClaimProofRequest(
                rHex: btcSig.rHex,
                sHex: btcSig.sHex,
                compressedPubkeyHex: input.btcCoin.hexPublicKey,
                utxos: input.utxos,
                claimerAddress: input.qbtcCoin.address,
                chainId: QBTCClaimConfig.chainId
            )
        )
        async let accountTask = fetchAccountInfo(input.qbtcCoin.address)
        let (proof, accountInfo) = try await (proofTask, accountTask)

        // Build the cosmos artifacts for the MLDSA round.
        let claimMessage = QBTCClaimMessage(
            claimer: input.qbtcCoin.address,
            utxos: input.utxos,
            proofHex: proof.proof,
            messageHashHex: proof.messageHash,
            addressHashHex: proof.addressHash,
            qbtcAddressHashHex: proof.qbtcAddressHash
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

    var errorDescription: String? {
        switch self {
        case .invalidBtcPublicKey:
            return "Invalid Bitcoin public key on the vault's BTC coin"
        case .invalidMldsaPublicKey:
            return "Invalid MLDSA public key on the vault's QBTC coin"
        }
    }
}
