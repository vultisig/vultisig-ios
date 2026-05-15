//
//  QBTCClaimSecureVaultRoundDriver.swift
//  VultisigApp
//
//  Production wiring for the SecureVault path of QBTC claim. The peer
//  device has already scanned the QR (which encoded the keysign payload
//  + qbtcClaimContext) and joined the relay session. This driver is
//  constructed AFTER that handshake — the screen passes the session
//  + participants in via init.
//
//  Post-qbtc#158: only one MPC round (BTC ECDSA via DKLS); the proof
//  service signs and broadcasts the cosmos tx.
//

import Foundation
import OSLog
import Tss

@MainActor
final class QBTCClaimSecureVaultRoundDriver {
    private let session: KeysignSessionInfo
    private let participants: [String]
    private let sessionService: KeysignSessionServicing
    private let logger = Logger(subsystem: "com.vultisig.app", category: "qbtc-securevault-driver")

    init(
        session: KeysignSessionInfo,
        participants: [String],
        sessionService: KeysignSessionServicing = KeysignSessionService()
    ) {
        self.session = session
        self.participants = participants
        self.sessionService = sessionService
    }

    // MARK: - BTC ECDSA round (DKLS)

    func runBtcRound(input: QBTCClaimBtcRoundInput) async throws -> QBTCClaimBtcRoundResult {
        // `KeysignDiscoveryView.startKeysign` already POSTed
        // `/start/{sessionId}` for us — this driver only needs to run
        // DKLS against the already-kicked-off session.
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
