//
//  QBTCClaimJoinDriver.swift
//  VultisigApp
//
//  Peer-side driver for the SecureVault QBTC claim flow. Constructed
//  after `JoinKeysignViewModel.handleQrCodeSuccessResult` detects a
//  `qbtcClaimContext` on the parsed `KeysignPayload` — the existing
//  one-QR-one-keysign flow steps aside and this driver runs the
//  single BTC ECDSA round.
//
//  Post-qbtc#158: only one MPC round (BTC ECDSA). The initiator
//  takes over after the round completes — POSTs `/prove` with
//  `broadcast: true` and the proof service signs + broadcasts the
//  cosmos tx with its own MLDSA-44 key. The peer device doesn't see
//  the broadcast directly; it just shows "Signing complete!" once
//  round 1 ends.
//
//  Flow:
//    1. `awaitRound1Start` — register as participant, poll
//       `/start/{baseSessionID}-0` until kickoff.
//    2. `runRound1` — DKLS keysign signing the locally-computed
//       `messageHashHex`. peer = isInitiateDevice: false.
//

import Foundation
import OSLog
import Tss

enum QBTCClaimJoinDriverError: LocalizedError {
    case missingBitcoinCoin
    case invalidCompressedPubkey
    case round1SignatureMissing

    var errorDescription: String? {
        switch self {
        case .missingBitcoinCoin:
            return "Vault is missing the Bitcoin coin needed for QBTC claim"
        case .invalidCompressedPubkey:
            return "Bitcoin compressed public key is malformed"
        case .round1SignatureMissing:
            return "Round 1 keysign completed without producing a signature"
        }
    }
}

@MainActor
final class QBTCClaimJoinDriver: ObservableObject {
    enum Phase: Equatable {
        case awaitingRound1Start
        case signingRound1
        case completed
        case failed(String)
    }

    @Published private(set) var phase: Phase = .awaitingRound1Start

    private let vault: Vault
    private let context: QBTCClaimContext
    private let baseSession: KeysignSessionInfo
    private let sessionService: KeysignSessionService
    private let logger = Logger(subsystem: "com.vultisig.app", category: "qbtc-claim-join")

    /// Cap on how long to wait for kickoff. Generous because the
    /// initiator may also be waiting on the user to confirm.
    static let kickoffTimeoutSeconds: TimeInterval = 600

    init(
        vault: Vault,
        context: QBTCClaimContext,
        baseSession: KeysignSessionInfo,
        sessionService: KeysignSessionService = KeysignSessionService()
    ) {
        self.vault = vault
        self.context = context
        self.baseSession = baseSession
        self.sessionService = sessionService
    }

    /// Drives the full peer-side flow. Mutates `phase` as it progresses.
    /// Errors transition to `.failed(message)`; the screen surfaces this.
    func run() async {
        do {
            try await runInternal()
        } catch is CancellationError {
            phase = .failed("Claim join cancelled")
        } catch {
            logger.error("Peer-side QBTC claim failed: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Internal flow

    private func runInternal() async throws {
        guard let btcCoin = vault.nativeCoin(for: .bitcoin) else {
            throw QBTCClaimJoinDriverError.missingBitcoinCoin
        }
        guard let compressedPubkey = Data(hexString: btcCoin.hexPublicKey) else {
            throw QBTCClaimJoinDriverError.invalidCompressedPubkey
        }

        // Compute round-1 message hash locally — this is what we sign.
        let hashes = try QBTCClaimHashes.computeAll(
            btcAddress: btcCoin.address,
            compressedPubkey: compressedPubkey,
            qbtcAddress: context.claimerAddress,
            chainId: QBTCClaimConfig.chainId
        )
        let messageHashHex = hashes.messageHash.toHexString()

        // BTC ECDSA round — wait for kickoff, run DKLS as a non-initiator.
        phase = .awaitingRound1Start
        let round1Session = sessionService.deriveRoundSession(from: baseSession, roundIndex: 0)
        try await sessionService.registerAsParticipant(session: round1Session)
        let round1Participants = try await sessionService.awaitKeysignStart(
            session: round1Session,
            timeout: Self.kickoffTimeoutSeconds
        )

        phase = .signingRound1
        try await runRound1(
            session: round1Session,
            participants: round1Participants,
            btcCoin: btcCoin,
            messageHashHex: messageHashHex
        )

        phase = .completed
    }

    // MARK: - Round runner (peer side)

    private func runRound1(
        session: KeysignSessionInfo,
        participants: [String],
        btcCoin: Coin,
        messageHashHex: String
    ) async throws {
        let derivePath = btcCoin.coinType.derivationPath()
        let dkls = DKLSKeysign(
            keysignCommittee: participants,
            mediatorURL: session.serverAddr,
            sessionID: session.sessionId,
            messsageToSign: [messageHashHex],
            vault: vault,
            encryptionKeyHex: session.encryptionKeyHex,
            chainPath: derivePath,
            isInitiateDevice: false,
            publicKeyECDSA: vault.pubKeyECDSA
        )
        try await dkls.DKLSKeysignWithRetry()
        guard dkls.getSignatures()[messageHashHex] != nil else {
            throw QBTCClaimJoinDriverError.round1SignatureMissing
        }
    }
}
