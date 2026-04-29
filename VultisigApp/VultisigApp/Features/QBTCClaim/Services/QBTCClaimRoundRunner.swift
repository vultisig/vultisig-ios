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

import Combine
import Foundation
import Mediator
import OSLog
import Tss

enum QBTCClaimRoundError: LocalizedError {
    case missingEncryptionKey
    case fastVaultPeerTimeout
    case signatureMissing(String)
    case malformedMldsaSignature(String)

    var errorDescription: String? {
        switch self {
        case .missingEncryptionKey:
            return "Failed to derive encryption key for MPC session"
        case .fastVaultPeerTimeout:
            return "Vultiserver did not join in time. Check your password and network and try again."
        case .signatureMissing(let hash):
            return "MPC session completed without producing a signature for \(hash)"
        case .malformedMldsaSignature(let hex):
            return "MLDSA signature was not valid hex: \(hex.prefix(16))…"
        }
    }
}

@MainActor
final class QBTCClaimRoundRunner {
    /// Cap on how long to wait for Vultiserver to register as a peer
    /// after `FastVaultService.sign` is POSTed. Matches the existing
    /// keysign UX expectation — the relay's `/start/{sessionId}` poll
    /// runs at 1-second intervals; Vultiserver typically joins within
    /// 5 s.
    static let fastVaultPeerWaitSeconds: TimeInterval = 60

    private let fastVaultService: FastVaultService
    private let mediator: Mediator
    private let logger = Logger(subsystem: "com.vultisig.app", category: "qbtc-round-runner")

    init(
        fastVaultService: FastVaultService = .shared,
        mediator: Mediator = .shared
    ) {
        self.fastVaultService = fastVaultService
        self.mediator = mediator
    }

    // MARK: - BTC ECDSA round (round 1)

    func runBtcRound(input: QBTCClaimBtcRoundInput) async throws -> QBTCClaimBtcRoundResult {
        let session = try makeSession(vault: input.vault)
        defer { session.discovery.stop() }

        let derivePath = input.btcCoin.coinType.derivationPath()
        try await fastVaultService.sign(
            publicKeyEcdsa: input.vault.pubKeyECDSA,
            keysignMessages: [input.messageHashHex],
            sessionID: session.sessionId,
            hexEncryptionKey: session.encryptionKeyHex,
            derivePath: derivePath,
            isECDSA: true,
            vaultPassword: input.fastVaultPassword,
            chain: input.btcCoin.chain.name
        )
        logger.info("FastVault sign POSTed for BTC round (session=\(session.sessionId, privacy: .public))")

        let participants = try await waitForFastVaultPeer(session: session)

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
        let session = try makeSession(vault: input.vault)
        defer { session.discovery.stop() }

        try await fastVaultService.sign(
            publicKeyEcdsa: input.vault.pubKeyECDSA,
            keysignMessages: [input.signDocHashHex],
            sessionID: session.sessionId,
            hexEncryptionKey: session.encryptionKeyHex,
            derivePath: QBTCClaimConfig.mldsaDerivePath,
            isECDSA: false,
            vaultPassword: input.fastVaultPassword,
            chain: input.qbtcCoin.chain.name
        )
        logger.info("FastVault sign POSTed for MLDSA round (session=\(session.sessionId, privacy: .public))")

        let participants = try await waitForFastVaultPeer(session: session)

        let dilithium = DilithiumKeysign(
            keysignCommittee: participants,
            mediatorURL: session.serverAddr,
            sessionID: session.sessionId,
            messageToSign: [input.signDocHashHex],
            vault: input.vault,
            encryptionKeyHex: session.encryptionKeyHex,
            chainPath: QBTCClaimConfig.mldsaDerivePath,
            isInitiateDevice: true,
            publicKey: input.vault.publicKeyMLDSA44 ?? ""
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

    // MARK: - Session bootstrap (FastVault, relay path)

    /// Per-round MPC session state. Each round MUST provision a fresh
    /// instance — the SignDoc hash signing key collides with the round-1
    /// hash on the relay if the sessionId is reused.
    private struct Session {
        let sessionId: String
        let encryptionKeyHex: String
        let serverAddr: String
        let serviceName: String
        let localPartyId: String
        let discovery: ParticipantDiscovery
    }

    private func makeSession(vault: Vault) throws -> Session {
        guard let key = Encryption.getEncryptionKey() else {
            throw QBTCClaimRoundError.missingEncryptionKey
        }
        let sessionId = UUID().uuidString
        let serviceName = "Vultisig-\(Int.random(in: 1...1000))"
        let localPartyId = vault.localPartyID.isEmpty
            ? Utils.getLocalDeviceIdentity()
            : vault.localPartyID

        // Mediator.start mirrors the existing keysign flow. For relay-only
        // FastVault this isn't strictly required for messaging (everything
        // goes through the relay), but we keep parity with the send flow
        // to avoid divergence in mediator state across the app.
        mediator.start(name: serviceName)

        return Session(
            sessionId: sessionId,
            encryptionKeyHex: key,
            serverAddr: Endpoint.vultisigRelay,
            serviceName: serviceName,
            localPartyId: localPartyId,
            discovery: ParticipantDiscovery()
        )
    }

    /// Polls `ParticipantDiscovery` for the Vultiserver peer joining the
    /// session. Returns `[localPartyId, serverPeerId, ...]` ready for
    /// `kickoffKeysign`. Throws on timeout.
    private func waitForFastVaultPeer(session: Session) async throws -> [String] {
        // Start polling the relay for participants.
        session.discovery.getParticipants(
            serverAddr: session.serverAddr,
            sessionID: session.sessionId,
            localParty: session.localPartyId
        )

        let started = Date()
        while session.discovery.peersFound.isEmpty {
            if Date().timeIntervalSince(started) > Self.fastVaultPeerWaitSeconds {
                throw QBTCClaimRoundError.fastVaultPeerTimeout
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        let participants = [session.localPartyId] + session.discovery.peersFound
        try await kickoffKeysign(session: session, participants: participants)
        return participants
    }

    /// POST `/start/{sessionId}` with the participant list — the relay
    /// uses this to signal "everyone has joined; start the keysign"
    /// to all peers.
    private func kickoffKeysign(session: Session, participants: [String]) async throws {
        let url = URL(string: "\(session.serverAddr)/start/\(session.sessionId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(participants)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw HelperError.runtimeError("kickoffKeysign returned non-2xx")
        }
    }
}

// MARK: - Convenience init wiring

extension QBTCClaimOrchestrator {
    /// Default production wiring. Tests should use the explicit closure
    /// initializer to inject mocks.
    @MainActor
    static func makeProduction() -> QBTCClaimOrchestrator {
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
}
