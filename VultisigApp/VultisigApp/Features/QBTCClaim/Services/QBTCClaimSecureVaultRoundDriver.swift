//
//  QBTCClaimSecureVaultRoundDriver.swift
//  VultisigApp
//
//  Production wiring for the SecureVault path of QBTC claim. The peer
//  device has already scanned the QR (which encoded the keysign payload
//  + qbtcClaimContext) and joined the relay session. This driver is
//  constructed AFTER that handshake — the screen passes the base session
//  + participants in via init.
//
//  Post-qbtc#158: only one MPC round (BTC ECDSA via DKLS); the proof
//  service signs and broadcasts the cosmos tx. The driver lives on
//  because SecureVault still uses the base-session-derive-per-round
//  pattern for relay namespacing, even though only round 0 is used.
//

import Foundation
import OSLog
import Tss

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

    // MARK: - BTC ECDSA round (DKLS)

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
}
