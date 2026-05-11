//
//  QBTCClaimRoundRunner.swift
//  VultisigApp
//
//  Production wiring for the orchestrator's BTC ECDSA round (the only
//  MPC round under post-qbtc#158: the proof service signs and broadcasts
//  `MsgClaimWithProof` with its own MLDSA-44 key). Provisions a fresh
//  MPC session (sessionId + encryption key), POSTs
//  `FastVaultService.sign(...)` to wake Vultiserver, awaits the server
//  peer via `ParticipantDiscovery`, kicks off the committee, then runs
//  DKLS.
//
//  No automated test — exercised by manual end-to-end on testnet (task
//  §14.3). Pure logic in `QBTCClaimOrchestrator` is what's unit tested
//  via injected closures.
//

import Foundation
import OSLog
import Tss

enum QBTCClaimRoundError: LocalizedError {
    case signatureMissing(String)

    var errorDescription: String? {
        switch self {
        case .signatureMissing(let hash):
            return String(format: "qbtcClaimErrorSignatureMissing".localized, hash)
        }
    }
}

@MainActor
final class QBTCClaimRoundRunner {
    /// Cap on how long to wait for Vultiserver to register as a peer
    /// after `FastVaultService.sign` is POSTed. Vultiserver typically
    /// joins within 5 s; the cap is a safety net.
    static let fastVaultPeerWaitSeconds: TimeInterval = 60

    private let sessionService: KeysignSessionService
    private let logger = Logger(subsystem: "com.vultisig.app", category: "qbtc-round-runner")

    init(sessionService: KeysignSessionService = KeysignSessionService()) {
        self.sessionService = sessionService
    }

    // MARK: - BTC ECDSA round

    func runBtcRound(input: QBTCClaimBtcRoundInput) async throws -> QBTCClaimBtcRoundResult {
        let session = try sessionService.newSession(vault: input.vault)
        let discovery = ParticipantDiscovery()
        defer { discovery.stop() }

        // Register on the relay BEFORE inviting Vultiserver. Without this POST, Vultiserver's
        // outbound MPC messages to this device's localPartyID may never be queued / matched
        // by the relay, and the iOS poll loop hangs on `/router/message/{sessionID}/{partyID}`
        // forever. Mirrors `FastVaultKeysignService.executeKeysignCeremony` step 1 and
        // `KeysignDiscoveryViewModel.startKeysignSession`.
        try await sessionService.registerAsParticipant(session: session)

        let derivePath = input.btcCoin.coinType.derivationPath()
        try await sessionService.wakeFastVaultServer(
            publicKeyEcdsa: input.vault.pubKeyECDSA,
            keysignMessages: [input.messageHashHex],
            session: session,
            derivePath: derivePath,
            isECDSA: true,
            vaultPassword: input.fastVaultPassword,
            chain: input.btcCoin.chain.name
        )

        let participants = try await sessionService.awaitFastVaultPeer(
            discovery: discovery,
            session: session,
            timeout: Self.fastVaultPeerWaitSeconds
        )
        try await sessionService.kickoffCommittee(session: session, participants: participants)

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

// MARK: - Convenience init wiring

extension QBTCClaimOrchestrator {
    /// Production wiring for the FastVault path. The orchestrator runs
    /// one DKLS BTC ECDSA round and then POSTs `/prove` with
    /// `broadcast: true`; the proof service signs the cosmos tx with
    /// its own MLDSA-44 key and broadcasts.
    @MainActor
    static func makeFastVault() -> QBTCClaimOrchestrator {
        let proofService = QBTCProofService()
        let runner = QBTCClaimRoundRunner()
        return QBTCClaimOrchestrator(
            generateProof: { try await proofService.generateProof($0) },
            runBtcRound: { try await runner.runBtcRound(input: $0) }
        )
    }

    /// Production wiring for the SecureVault path. The base session and
    /// participants come from the QR handshake — the peer device has
    /// already scanned and joined the relay. The orchestrator runs one
    /// DKLS BTC ECDSA round on `{baseSession.sessionId}-0` and then
    /// POSTs `/prove` with `broadcast: true`.
    @MainActor
    static func makeSecureVault(
        baseSession: KeysignSessionInfo,
        participants: [String]
    ) -> QBTCClaimOrchestrator {
        let proofService = QBTCProofService()
        let driver = QBTCClaimSecureVaultRoundDriver(
            baseSession: baseSession,
            participants: participants
        )
        return QBTCClaimOrchestrator(
            generateProof: { try await proofService.generateProof($0) },
            runBtcRound: { try await driver.runBtcRound(input: $0) }
        )
    }

    /// Backwards-compatible alias for FastVault wiring. Older callers
    /// (the v1 ViewModel) used `makeProduction()`.
    @MainActor
    static func makeProduction() -> QBTCClaimOrchestrator {
        makeFastVault()
    }
}
