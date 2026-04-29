//
//  QBTCClaimSecureVaultRoundDriver.swift
//  VultisigApp
//
//  Production wiring for the SecureVault path of QBTC claim. The peer
//  device has already scanned the QR (which encoded round-1's keysign
//  payload + qbtcClaimContext) and joined the relay session. This driver
//  is constructed AFTER that handshake — the screen passes the base
//  session + participants in via init.
//
//  Both rounds reuse the base session — round 1 runs on
//  `{baseSessionID}-0` (DKLS / ECDSA), round 2 on `{baseSessionID}-1`
//  (Dilithium / MLDSA). Each round's TSS protocol gets its own clean
//  relay namespace so messages don't cross-contaminate.
//
//  Between rounds, the driver pushes round-2 prep (proof + hashes +
//  account number + sequence) to the peer via the relay's
//  `/setup-message/{baseSessionID}-1` slot. The peer reconstructs
//  round-2's SignDoc from this + round-1's qbtcClaimContext.
//
//  See [[projects/vultisig/qbtc-claim/v2-secure-vault-design]].
//

import Foundation
import OSLog
import Tss

/// Message id used for the round-2 prep relay-message slot.
/// Both initiator and peer agree on this string.
let qbtcClaimRound2PrepMessageID = "qbtc-claim-round2-prep"

@MainActor
final class QBTCClaimSecureVaultRoundDriver {
    private let baseSession: KeysignSessionInfo
    private let participants: [String]
    private let sessionService: KeysignSessionService
    private let logger = Logger(subsystem: "com.vultisig.app", category: "qbtc-securevault-driver")

    init(
        baseSession: KeysignSessionInfo,
        participants: [String],
        sessionService: KeysignSessionService = KeysignSessionService()
    ) {
        self.baseSession = baseSession
        self.participants = participants
        self.sessionService = sessionService
    }

    // MARK: - Round 1 (BTC ECDSA, DKLS)

    func runBtcRound(input: QBTCClaimBtcRoundInput) async throws -> QBTCClaimBtcRoundResult {
        let session = sessionService.deriveRoundSession(from: baseSession, roundIndex: 0)
        try await sessionService.kickoffCommittee(session: session, participants: participants)

        let derivePath = input.btcCoin.coinType.derivationPath()
        let dkls = DKLSKeysign(
            keysignCommittee: participants,
            mediatorURL: session.serverAddr,
            sessionID: session.sessionId,
            messsageToSign: [input.messageHashHex],
            vault: input.vault,
            encryptionKeyHex: session.encryptionKeyHex,
            chainPath: derivePath,
            isInitiateDevice: true,
            publicKeyECDSA: input.vault.pubKeyECDSA
        )
        try await dkls.DKLSKeysignWithRetry()

        let signatures = dkls.getSignatures()
        guard let sig = signatures[input.messageHashHex] else {
            throw QBTCClaimRoundError.signatureMissing(input.messageHashHex)
        }
        return QBTCClaimBtcRoundResult(rHex: sig.r, sHex: sig.s)
    }

    // MARK: - Round 2 (MLDSA, Dilithium)

    func runMldsaRound(input: QBTCClaimMldsaRoundInput) async throws -> Data {
        guard let mldsaPublicKey = input.vault.publicKeyMLDSA44, !mldsaPublicKey.isEmpty else {
            throw QBTCClaimRoundError.missingMldsaPublicKey
        }
        let session = sessionService.deriveRoundSession(from: baseSession, roundIndex: 1)
        try await sessionService.kickoffCommittee(session: session, participants: participants)

        let dilithium = DilithiumKeysign(
            keysignCommittee: participants,
            mediatorURL: session.serverAddr,
            sessionID: session.sessionId,
            messageToSign: [input.signDocHashHex],
            vault: input.vault,
            encryptionKeyHex: session.encryptionKeyHex,
            chainPath: QBTCClaimConfig.mldsaDerivePath,
            isInitiateDevice: true,
            publicKey: mldsaPublicKey
        )
        try await dilithium.DilithiumKeysignWithRetry()

        let signatures = dilithium.getSignatures()
        guard let response = signatures[input.signDocHashHex] else {
            throw QBTCClaimRoundError.signatureMissing(input.signDocHashHex)
        }
        guard let signatureBytes = Data(hexString: response.signature) else {
            throw QBTCClaimRoundError.malformedMldsaSignature(response.signature)
        }
        return signatureBytes
    }

    // MARK: - Round 2 prep push

    /// Publishes the round-2 prep message to the peer device via the
    /// relay's setup-message slot for `{baseSessionID}-1`. Encrypted
    /// with the same `encryptionKeyHex` the peer derives from the QR.
    func pushRound2Prep(_ prep: QBTCClaimRound2Prep) async throws {
        let json = try JSONEncoder().encode(prep)
        let round2Session = sessionService.deriveRoundSession(from: baseSession, roundIndex: 1)
        try await sessionService.pushSetupMessage(
            session: round2Session,
            messageID: qbtcClaimRound2PrepMessageID,
            body: json
        )
    }
}
