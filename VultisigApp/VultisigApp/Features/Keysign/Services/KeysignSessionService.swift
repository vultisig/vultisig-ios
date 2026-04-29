//
//  KeysignSessionService.swift
//  VultisigApp
//
//  Service-shaped extraction of the relay-session bootstrap from
//  `KeysignDiscoveryViewModel.setData` and `QBTCClaimRoundRunner`.
//  Owns: mediator start, sessionID + encryption-key generation, the
//  Vultiserver wake-up call, the relay-session "I'm here" POST, the
//  kickoff `/start/{sessionId}` POST, and peer-discovery awaiting.
//
//  Both the existing single-round keysign discovery flow (send / swap
//  / function-call paths) and the QBTC claim flow (single-round in v1,
//  multi-round in v2) delegate to this service so the bootstrap logic
//  has one source of truth.
//

import Combine
import Foundation
import Mediator
import OSLog

/// Bootstrap state for one MPC session — handed back from `newSession`
/// and threaded through the rest of the calls. Value type; safe to
/// pass across actor boundaries.
struct KeysignSessionInfo: Equatable {
    let sessionId: String
    let encryptionKeyHex: String
    let serviceName: String
    let localPartyId: String
    let serverAddr: String
}

enum KeysignSessionServiceError: LocalizedError {
    case missingEncryptionKey
    case fastVaultPeerTimeout
    case startSessionFailed(statusCode: Int)
    case kickoffFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .missingEncryptionKey:
            return "Failed to derive encryption key for MPC session"
        case .fastVaultPeerTimeout:
            return "Vultiserver did not join the MPC session in time. Check your password and network and try again."
        case .startSessionFailed(let code):
            return "Failed to register with the relay (status \(code))"
        case .kickoffFailed(let code):
            return "Failed to kick off the keysign committee (status \(code))"
        }
    }
}

@MainActor
final class KeysignSessionService {
    private let mediator: Mediator
    private let fastVaultService: FastVaultService
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "com.vultisig.app", category: "keysign-session")

    nonisolated init(
        mediator: Mediator = .shared,
        fastVaultService: FastVaultService = .shared,
        urlSession: URLSession = .shared
    ) {
        self.mediator = mediator
        self.fastVaultService = fastVaultService
        self.urlSession = urlSession
    }

    // MARK: - Session creation

    /// Provisions a fresh session: generates `sessionId`, encryption key,
    /// and service name; starts the local mediator (no-op for relay-only
    /// FastVault flows but kept for parity with the existing send flow).
    /// Server addr defaults to the Vultisig relay.
    func newSession(vault: Vault, serviceName: String? = nil) throws -> KeysignSessionInfo {
        guard let encryptionKeyHex = Encryption.getEncryptionKey() else {
            throw KeysignSessionServiceError.missingEncryptionKey
        }
        let sessionId = UUID().uuidString
        let resolvedServiceName = serviceName ?? "Vultisig-\(Int.random(in: 1...1000))"
        let localPartyId = vault.localPartyID.isEmpty
            ? Utils.getLocalDeviceIdentity()
            : vault.localPartyID

        mediator.start(name: resolvedServiceName)

        return KeysignSessionInfo(
            sessionId: sessionId,
            encryptionKeyHex: encryptionKeyHex,
            serviceName: resolvedServiceName,
            localPartyId: localPartyId,
            serverAddr: Endpoint.vultisigRelay
        )
    }

    /// Derives a per-round session from a base session id (used by the
    /// multi-round QBTC claim flow). Encryption key and local party id
    /// are reused across rounds; the relay sessionId gets a `-{round}`
    /// suffix so each TSS protocol runs in its own clean namespace.
    func deriveRoundSession(
        from base: KeysignSessionInfo,
        roundIndex: Int
    ) -> KeysignSessionInfo {
        KeysignSessionInfo(
            sessionId: "\(base.sessionId)-\(roundIndex)",
            encryptionKeyHex: base.encryptionKeyHex,
            serviceName: base.serviceName,
            localPartyId: base.localPartyId,
            serverAddr: base.serverAddr
        )
    }

    // MARK: - Vultiserver wake-up (FastVault)

    /// POSTs `signWithServer` to wake the Vultiserver as the second MPC
    /// share for the given keysign messages. Caller is responsible for
    /// awaiting the server's join via `awaitFastVaultPeer(...)` next.
    func wakeFastVaultServer(
        publicKeyEcdsa: String,
        keysignMessages: [String],
        session: KeysignSessionInfo,
        derivePath: String,
        isECDSA: Bool,
        vaultPassword: String,
        chain: String
    ) async throws {
        try await fastVaultService.sign(
            publicKeyEcdsa: publicKeyEcdsa,
            keysignMessages: keysignMessages,
            sessionID: session.sessionId,
            hexEncryptionKey: session.encryptionKeyHex,
            derivePath: derivePath,
            isECDSA: isECDSA,
            vaultPassword: vaultPassword,
            chain: chain
        )
        logger.info("FastVault sign POSTed (session=\(session.sessionId, privacy: .public), isECDSA=\(isECDSA, privacy: .public))")
    }

    // MARK: - Relay-session lifecycle

    /// POST `{serverAddr}/{sessionId}` with `[localPartyId]` — the
    /// "I'm here" signal that registers this device as a participant.
    /// Existing send/swap flows do this from
    /// `KeysignDiscoveryViewModel.startKeysignSession`; QBTC claim
    /// (round runner + future v2 peer side) does it via this method.
    func registerAsParticipant(session: KeysignSessionInfo) async throws {
        let url = URL(string: "\(session.serverAddr)/\(session.sessionId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([session.localPartyId])

        let (_, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw KeysignSessionServiceError.startSessionFailed(statusCode: code)
        }
    }

    /// POST `{serverAddr}/start/{sessionId}` with the participant list —
    /// the relay's "everyone has joined; start the keysign" trigger.
    func kickoffCommittee(session: KeysignSessionInfo, participants: [String]) async throws {
        let url = URL(string: "\(session.serverAddr)/start/\(session.sessionId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(participants)

        let (_, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw KeysignSessionServiceError.kickoffFailed(statusCode: code)
        }
        logger.info("Kickoff sent (session=\(session.sessionId, privacy: .public), participants=\(participants.count))")
    }

    // MARK: - Peer awaiting

    /// Polls a `ParticipantDiscovery` for the second MPC share to join
    /// (Vultiserver in FastVault flows; the peer device in SecureVault
    /// flows). Returns `[localPartyId, ...peers]` ready for `kickoffCommittee`.
    /// Throws `fastVaultPeerTimeout` after the cap (default 60 s).
    func awaitFastVaultPeer(
        discovery: ParticipantDiscovery,
        session: KeysignSessionInfo,
        timeout: TimeInterval = 60
    ) async throws -> [String] {
        discovery.getParticipants(
            serverAddr: session.serverAddr,
            sessionID: session.sessionId,
            localParty: session.localPartyId
        )

        let started = Date()
        while discovery.peersFound.isEmpty {
            if Date().timeIntervalSince(started) > timeout {
                throw KeysignSessionServiceError.fastVaultPeerTimeout
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        return [session.localPartyId] + discovery.peersFound
    }
}
