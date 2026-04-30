//
//  QBTCClaimJoinDriver.swift
//  VultisigApp
//
//  Peer-side driver for the SecureVault QBTC claim flow. Constructed
//  after `JoinKeysignViewModel.handleQrCodeSuccessResult` detects a
//  `qbtcClaimContext` on the parsed `KeysignPayload` — the existing
//  one-QR-one-keysign flow steps aside and this driver runs both
//  rounds with a wait + verify between them.
//
//  Flow:
//    1. `awaitRound1Start` — register as participant, poll
//       `/start/{baseSessionID}-0` until kickoff.
//    2. `runRound1` — DKLS keysign signing the locally-computed
//       `messageHashHex`. peer = isInitiateDevice: false.
//    3. `awaitRound2Prep` — poll `/setup-message/{baseSessionID}-1`
//       for the round-2 prep (proof + hashes + accountNumber/sequence).
//    4. `verifyAndBuild` — compare prep's `messageHashHex` to ours,
//       reconstruct round-2 SignDoc, capture `signDocHashHex`.
//    5. `awaitRound2Start` — register, wait for kickoff on `-1`.
//    6. `runRound2` — Dilithium keysign signing the SignDoc hash.
//
//  See [[projects/vultisig/qbtc-claim/v2-secure-vault-design]].
//

import Foundation
import OSLog
import Tss

enum QBTCClaimJoinDriverError: LocalizedError {
    case missingBitcoinCoin
    case invalidCompressedPubkey
    case missingMldsaPubkey
    case messageHashMismatch(expected: String, got: String)
    case round1SignatureMissing
    case round2SignatureMissing

    var errorDescription: String? {
        switch self {
        case .missingBitcoinCoin:
            return "Vault is missing the Bitcoin coin needed for QBTC claim"
        case .invalidCompressedPubkey:
            return "Bitcoin compressed public key is malformed"
        case .missingMldsaPubkey:
            return "Vault is missing the ML-DSA public key needed for QBTC claim"
        case .messageHashMismatch(let expected, let got):
            return "Round-2 prep is for a different claim than round 1. Expected message hash \(expected.prefix(16))…, got \(got.prefix(16))…"
        case .round1SignatureMissing:
            return "Round 1 keysign completed without producing a signature"
        case .round2SignatureMissing:
            return "Round 2 keysign completed without producing a signature"
        }
    }
}

@MainActor
final class QBTCClaimJoinDriver: ObservableObject {
    enum Phase: Equatable {
        case awaitingRound1Start
        case signingRound1
        case awaitingRound2Prep
        case verifyingRound2Prep
        case awaitingRound2Start
        case signingRound2
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
    /// Cap on how long to wait for the round-2 prep. The proof service
    /// has a 300 s deadline — we double it to give the initiator headroom.
    static let round2PrepTimeoutSeconds: TimeInterval = 600

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
        guard let mldsaPubkeyHex = vault.publicKeyMLDSA44, !mldsaPubkeyHex.isEmpty,
              let mldsaPubkey = Data(hexString: mldsaPubkeyHex) else {
            throw QBTCClaimJoinDriverError.missingMldsaPubkey
        }

        // Compute round-1 message hash locally — this is what we sign.
        let hashes = try QBTCClaimHashes.computeAll(
            btcAddress: btcCoin.address,
            compressedPubkey: compressedPubkey,
            qbtcAddress: context.claimerAddress,
            chainId: QBTCClaimConfig.chainId
        )
        let messageHashHex = hashes.messageHash.toHexString()

        // Round 1 — wait for kickoff, run DKLS as a non-initiator.
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

        // Round 2 — wait for the prep, verify, build SignDoc hash.
        phase = .awaitingRound2Prep
        let round2Session = sessionService.deriveRoundSession(from: baseSession, roundIndex: 1)
        let prepData = try await sessionService.pollSetupMessage(
            session: round2Session,
            messageID: qbtcClaimRound2PrepMessageID,
            timeout: Self.round2PrepTimeoutSeconds
        )
        let prep = try JSONDecoder().decode(QBTCClaimRound2Prep.self, from: prepData)

        phase = .verifyingRound2Prep
        guard prep.messageHashHex == messageHashHex else {
            throw QBTCClaimJoinDriverError.messageHashMismatch(
                expected: messageHashHex,
                got: prep.messageHashHex
            )
        }
        let signDocHashHex = try buildRound2SignDocHashHex(prep: prep, mldsaPubkey: mldsaPubkey)

        // Round 2 — wait for kickoff, run Dilithium as a non-initiator.
        phase = .awaitingRound2Start
        try await sessionService.registerAsParticipant(session: round2Session)
        let round2Participants = try await sessionService.awaitKeysignStart(
            session: round2Session,
            timeout: Self.kickoffTimeoutSeconds
        )

        phase = .signingRound2
        try await runRound2(
            session: round2Session,
            participants: round2Participants,
            signDocHashHex: signDocHashHex
        )

        phase = .completed
    }

    // MARK: - Round runners (peer side)

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

    private func runRound2(
        session: KeysignSessionInfo,
        participants: [String],
        signDocHashHex: String
    ) async throws {
        let dilithium = DilithiumKeysign(
            keysignCommittee: participants,
            mediatorURL: session.serverAddr,
            sessionID: session.sessionId,
            messageToSign: [signDocHashHex],
            vault: vault,
            encryptionKeyHex: session.encryptionKeyHex,
            chainPath: QBTCClaimConfig.mldsaDerivePath,
            isInitiateDevice: false,
            publicKey: vault.publicKeyMLDSA44 ?? ""
        )
        try await dilithium.DilithiumKeysignWithRetry()
        guard dilithium.getSignatures()[signDocHashHex] != nil else {
            throw QBTCClaimJoinDriverError.round2SignatureMissing
        }
    }

    // MARK: - Round 2 SignDoc reconstruction

    private func buildRound2SignDocHashHex(
        prep: QBTCClaimRound2Prep,
        mldsaPubkey: Data
    ) throws -> String {
        let claimMessage = QBTCClaimMessage(
            claimer: context.claimerAddress,
            utxos: context.utxos,
            proofHex: prep.proofHex,
            messageHashHex: prep.messageHashHex,
            addressHashHex: prep.addressHashHex,
            qbtcAddressHashHex: prep.qbtcAddressHashHex,
            pubKeyHashSha256Hex: prep.pubKeyHashSha256Hex
        )
        let bodyBytes = try QBTCHelper.buildClaimTxBody(claimMessage)
        let artifacts = QBTCHelper.buildClaimSignDoc(
            bodyBytes: bodyBytes,
            mldsaPublicKey: mldsaPubkey,
            accountNumber: prep.accountNumber,
            sequence: prep.sequence
        )
        return artifacts.signDocHashHex
    }
}
