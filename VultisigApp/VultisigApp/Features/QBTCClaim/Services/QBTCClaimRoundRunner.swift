//
//  QBTCClaimRoundRunner.swift
//  VultisigApp
//
//  Production wiring for the orchestrator's two MPC sign rounds.
//  Each round provisions a fresh MPC session (sessionId + encryption
//  key), POSTs `FastVaultService.sign(...)` to wake Vultiserver, awaits
//  the server peer via `ParticipantDiscovery`, kicks off the committee,
//  then runs the appropriate TSS driver. v1 supports FastVault only;
//  SecureVault is deferred to v2 (see spec design.md).
//
//  No automated test — exercised by manual end-to-end on testnet
//  (task §14.3). Pure logic in `QBTCClaimOrchestrator` is what's unit
//  tested via injected closures.
//

import Foundation
import OSLog
import Tss

enum QBTCClaimRoundError: LocalizedError {
    case missingMldsaPublicKey
    case signatureMissing(String)
    case malformedMldsaSignature(String)

    var errorDescription: String? {
        switch self {
        case .missingMldsaPublicKey:
            return "qbtcClaimErrorMissingMldsaPublicKey".localized
        case .signatureMissing(let hash):
            return String(format: "qbtcClaimErrorSignatureMissing".localized, hash)
        case .malformedMldsaSignature(let hex):
            return String(format: "qbtcClaimErrorMalformedMldsaSignature".localized, String(hex.prefix(16)))
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

    // MARK: - BTC ECDSA round (round 1)

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

    // MARK: - MLDSA round (round 2)

    func runMldsaRound(input: QBTCClaimMldsaRoundInput) async throws -> Data {
        guard let mldsaPublicKey = input.vault.publicKeyMLDSA44, !mldsaPublicKey.isEmpty else {
            throw QBTCClaimRoundError.missingMldsaPublicKey
        }
        let session = try sessionService.newSession(vault: input.vault)
        let discovery = ParticipantDiscovery()
        defer { discovery.stop() }

        // See `runBtcRound` for why we register before inviting Vultiserver.
        try await sessionService.registerAsParticipant(session: session)

        try await sessionService.wakeFastVaultServer(
            publicKeyEcdsa: input.vault.pubKeyECDSA,
            keysignMessages: [input.signDocHashHex],
            session: session,
            derivePath: QBTCClaimConfig.mldsaDerivePath,
            isECDSA: false,
            vaultPassword: input.fastVaultPassword,
            chain: input.qbtcCoin.chain.name
        )

        let participants = try await sessionService.awaitFastVaultPeer(
            discovery: discovery,
            session: session,
            timeout: Self.fastVaultPeerWaitSeconds
        )
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
}

// MARK: - Convenience init wiring

extension QBTCClaimOrchestrator {
    /// Production wiring for the FastVault path. Both rounds use
    /// independent sessions; Vultiserver acts as the second share.
    /// `pushRound2Prep` is a no-op (Vultiserver is woken via two
    /// `signWithServer` POSTs instead of a relay setup-message).
    @MainActor
    static func makeFastVault() -> QBTCClaimOrchestrator {
        let proofService = QBTCProofService()
        let chainService = QBTCChainService()
        let runner = QBTCClaimRoundRunner()
        return QBTCClaimOrchestrator(
            generateProof: { try await proofService.generateProof($0) },
            fetchAccountInfo: { try await chainService.getAccountInfoForClaim(qbtcAddress: $0) },
            broadcastClaim: { txRawBytes, txHashHex in
                try await chainService.broadcastClaim(
                    txBytesBase64: txRawBytes.base64EncodedString(),
                    txHashHex: txHashHex
                )
            },
            runBtcRound: { try await runner.runBtcRound(input: $0) },
            runMldsaRound: { try await runner.runMldsaRound(input: $0) }
        )
    }

    /// Production wiring for the SecureVault path. Both rounds share
    /// the base session (per-round IDs derive from
    /// `{baseSession.sessionId}-{round}`); the peer device has already
    /// scanned the QR and joined the relay (this is what makes
    /// `participants` known here). `pushRound2Prep` writes the
    /// proof+hashes+account info to the relay's setup-message slot
    /// so the peer can reconstruct round-2's SignDoc.
    @MainActor
    static func makeSecureVault(
        baseSession: KeysignSessionInfo,
        participants: [String]
    ) -> QBTCClaimOrchestrator {
        let proofService = QBTCProofService()
        let chainService = QBTCChainService()
        let driver = QBTCClaimSecureVaultRoundDriver(
            baseSession: baseSession,
            participants: participants
        )
        return QBTCClaimOrchestrator(
            generateProof: { try await proofService.generateProof($0) },
            fetchAccountInfo: { try await chainService.getAccountInfoForClaim(qbtcAddress: $0) },
            broadcastClaim: { txRawBytes, txHashHex in
                try await chainService.broadcastClaim(
                    txBytesBase64: txRawBytes.base64EncodedString(),
                    txHashHex: txHashHex
                )
            },
            runBtcRound: { try await driver.runBtcRound(input: $0) },
            runMldsaRound: { try await driver.runMldsaRound(input: $0) },
            pushRound2Prep: { try await driver.pushRound2Prep($0) }
        )
    }

    /// Backwards-compatible alias for FastVault wiring. Older callers
    /// (the v1 ViewModel) used `makeProduction()`.
    @MainActor
    static func makeProduction() -> QBTCClaimOrchestrator {
        makeFastVault()
    }
}
