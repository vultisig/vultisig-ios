//
//  QBTCClaimJoinDriver.swift
//  VultisigApp
//
//  Peer-side driver for the SecureVault QBTC claim flow. Constructed
//  after `JoinKeysignViewModel.handleQrCodeSuccessResult` detects
//  `isQbtcClaim == true` on the parsed `KeysignPayload` — the existing
//  one-QR-one-keysign flow steps aside and this driver runs the single
//  BTC ECDSA round. The claimer's QBTC address is derived from the
//  peer's own vault (same SecureVault → same QBTC coin).
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
//       `/start/{sessionID}` until kickoff.
//    2. `runRound1` — DKLS keysign signing the locally-computed
//       `messageHashHex`. peer = isInitiateDevice: false.
//

import Foundation
import OSLog
import Tss

enum QBTCClaimJoinDriverError: LocalizedError {
    case missingBitcoinCoin
    case missingQbtcCoin
    case invalidCompressedPubkey
    case round1SignatureMissing

    var errorDescription: String? {
        switch self {
        case .missingBitcoinCoin:
            return "Vault is missing the Bitcoin coin needed for QBTC claim"
        case .missingQbtcCoin:
            return "Vault is missing the QBTC coin needed to derive the claimer address"
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
        /// Set once DKLS completes. `result` carries the initiator's
        /// broadcast tx hash + claim total if the relay push arrived
        /// within the poll window, or nil on timeout.
        case completed(result: QBTCClaimRunResult?)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .awaitingRound1Start

    /// Cap on how long the peer waits for the initiator's tx-hash push
    /// after DKLS completes. The proof service typically returns in a
    /// few seconds; the upper bound covers slow-network worst case.
    static let resultPollTimeoutSeconds: TimeInterval = 60

    /// Exposed so the peer-side view can build the shared
    /// `QBTCClaimDoneScreen` once the run completes.
    let vault: Vault
    private let session: KeysignSessionInfo
    private let sessionService: KeysignSessionServicing
    private let logger = Logger(subsystem: "com.vultisig.app", category: "qbtc-claim-join")

    /// Cap on how long to wait for kickoff. Generous because the
    /// initiator may also be waiting on the user to confirm.
    static let kickoffTimeoutSeconds: TimeInterval = 600

    init(
        vault: Vault,
        session: KeysignSessionInfo,
        sessionService: KeysignSessionServicing = KeysignSessionService()
    ) {
        self.vault = vault
        self.session = session
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
        // Derive the claimer's QBTC address from the peer's own vault — both
        // initiator and peer share the same SecureVault, so the QBTC coin
        // (and thus its derived address) is the same across devices. No need
        // to round-trip it through the keysign payload.
        guard let qbtcCoin = vault.nativeCoin(for: .qbtc) else {
            throw QBTCClaimJoinDriverError.missingQbtcCoin
        }
        guard let compressedPubkey = Data(hexString: btcCoin.hexPublicKey) else {
            throw QBTCClaimJoinDriverError.invalidCompressedPubkey
        }

        // Compute round-1 message hash locally — this is what we sign.
        let hashes = try QBTCClaimHashes.computeAll(
            btcAddress: btcCoin.address,
            compressedPubkey: compressedPubkey,
            qbtcAddress: qbtcCoin.address,
            chainId: QBTCClaimConfig.chainId
        )
        let messageHashHex = hashes.messageHash.toHexString()

        // BTC ECDSA round — wait for kickoff, run DKLS as a non-initiator.
        phase = .awaitingRound1Start
        try await sessionService.registerAsParticipant(session: session)
        let round1Participants = try await sessionService.awaitKeysignStart(
            session: session,
            timeout: Self.kickoffTimeoutSeconds
        )

        phase = .signingRound1
        try await runRound1(
            session: session,
            participants: round1Participants,
            btcCoin: btcCoin,
            messageHashHex: messageHashHex
        )

        // Poll for the initiator's tx-hash push so the peer's done
        // screen can render the same status header + explorer link.
        // Best-effort: a timeout still completes; the done screen
        // gracefully falls back to a hashless variant.
        let result = await pollForResult()
        phase = .completed(result: result)
    }

    private func pollForResult() async -> QBTCClaimRunResult? {
        do {
            let data = try await sessionService.pollSetupMessage(
                session: session,
                messageID: QBTCClaimResultMessage.messageID,
                timeout: Self.resultPollTimeoutSeconds
            )
            let message = try JSONDecoder().decode(QBTCClaimResultMessage.self, from: data)
            return QBTCClaimRunResult(
                txHashHex: message.txHash,
                totalSatsClaimed: message.totalSats
            )
        } catch {
            logger.warning("Tx-hash push not received within \(Self.resultPollTimeoutSeconds, privacy: .public)s: \(error.localizedDescription)")
            return nil
        }
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
