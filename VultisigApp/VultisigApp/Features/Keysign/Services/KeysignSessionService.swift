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
    case kickoffTimeout
    case invalidSetupMessageBody
    case setupMessageEncryptFailed
    case setupMessageDecryptFailed
    case setupMessageTimeout

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
        case .kickoffTimeout:
            return "The initiator did not start the keysign committee in time."
        case .invalidSetupMessageBody:
            return "Setup message body was not valid UTF-8"
        case .setupMessageEncryptFailed:
            return "Failed to encrypt setup message body"
        case .setupMessageDecryptFailed:
            return "Failed to decrypt setup message body"
        case .setupMessageTimeout:
            return "Timed out waiting for the setup message from the initiator"
        }
    }
}

@MainActor
final class KeysignSessionService {
    private let mediator: Mediator
    private let fastVaultService: FastVaultService
    private let httpClient: HTTPClientProtocol
    private let logger = Logger(subsystem: "com.vultisig.app", category: "keysign-session")

    nonisolated init(
        mediator: Mediator = .shared,
        fastVaultService: FastVaultService = .shared,
        httpClient: HTTPClientProtocol = HTTPClient()
    ) {
        self.mediator = mediator
        self.fastVaultService = fastVaultService
        self.httpClient = httpClient
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
        chain: String,
        isMldsa: Bool = false
    ) async throws {
        try await fastVaultService.sign(
            publicKeyEcdsa: publicKeyEcdsa,
            keysignMessages: keysignMessages,
            sessionID: session.sessionId,
            hexEncryptionKey: session.encryptionKeyHex,
            derivePath: derivePath,
            isECDSA: isECDSA,
            vaultPassword: vaultPassword,
            chain: chain,
            isMldsa: isMldsa
        )
        logger.info("FastVault sign POSTed (session=\(session.sessionId, privacy: .public), isECDSA=\(isECDSA, privacy: .public), isMldsa=\(isMldsa, privacy: .public))")
    }

    // MARK: - Relay-session lifecycle

    /// POST `{serverAddr}/{sessionId}` with `[localPartyId]` — the
    /// "I'm here" signal that registers this device as a participant.
    /// Existing send/swap flows do this from
    /// `KeysignDiscoveryViewModel.startKeysignSession`; QBTC claim
    /// (round runner + future v2 peer side) does it via this method.
    func registerAsParticipant(session: KeysignSessionInfo) async throws {
        guard let baseURL = URL(string: session.serverAddr) else {
            throw KeysignSessionServiceError.startSessionFailed(statusCode: -1)
        }
        let body = try JSONEncoder().encode([session.localPartyId])
        do {
            _ = try await httpClient.request(
                RelayServerAPI(
                    baseURL: baseURL,
                    endpoint: .registerAsParticipant(sessionID: session.sessionId, body: body)
                )
            )
        } catch let HTTPError.statusCode(code, _) {
            throw KeysignSessionServiceError.startSessionFailed(statusCode: code)
        }
    }

    /// POST `{serverAddr}/start/{sessionId}` with the participant list —
    /// the relay's "everyone has joined; start the keysign" trigger.
    func kickoffCommittee(session: KeysignSessionInfo, participants: [String]) async throws {
        guard let baseURL = URL(string: session.serverAddr) else {
            throw KeysignSessionServiceError.kickoffFailed(statusCode: -1)
        }
        let body = try JSONEncoder().encode(participants)
        do {
            _ = try await httpClient.request(
                RelayServerAPI(
                    baseURL: baseURL,
                    endpoint: .startSession(sessionID: session.sessionId, body: body)
                )
            )
        } catch let HTTPError.statusCode(code, _) {
            throw KeysignSessionServiceError.kickoffFailed(statusCode: code)
        }
        logger.info("Kickoff sent (session=\(session.sessionId, privacy: .public), participants=\(participants.count))")
    }

    // MARK: - Out-of-band relay messages
    //
    // Used by the multi-round QBTC claim flow to push round-2 prep
    // (proof + hashes + account info) from the initiator to the peer
    // device between rounds. The relay's `/setup-message/{sessionID}`
    // endpoint holds the encrypted body until the peer downloads it
    // — fits the "send a payload before the next keysign starts" use
    // case exactly. Body is AES-GCM-encrypted with `session.encryptionKeyHex`.

    /// Uploads an encrypted out-of-band message to the relay's
    /// setup-message slot for the given session and `messageID`.
    /// The peer downloads it via the symmetric `/setup-message`
    /// GET path with the same `messageID` header.
    func pushSetupMessage(
        session: KeysignSessionInfo,
        messageID: String,
        body: Data
    ) async throws {
        guard let plaintext = String(data: body, encoding: .utf8) else {
            throw KeysignSessionServiceError.invalidSetupMessageBody
        }
        guard let encryptedBody = plaintext.aesEncryptGCM(key: session.encryptionKeyHex),
              let encryptedData = encryptedBody.data(using: .utf8) else {
            throw KeysignSessionServiceError.setupMessageEncryptFailed
        }
        guard let baseURL = URL(string: session.serverAddr) else {
            throw KeysignSessionServiceError.startSessionFailed(statusCode: -1)
        }
        let httpClient = HTTPClient()
        do {
            _ = try await httpClient.request(TssRelayAPI(
                baseURL: baseURL,
                endpoint: .uploadSetupMessage(
                    sessionID: session.sessionId,
                    body: encryptedData,
                    messageID: messageID,
                    additionalHeader: nil
                )
            ))
        } catch let HTTPError.statusCode(code, _) {
            throw KeysignSessionServiceError.startSessionFailed(statusCode: code)
        }
        logger.info("Pushed relay setup-message (session=\(session.sessionId, privacy: .public), messageID=\(messageID, privacy: .public))")
    }

    /// Pulls an out-of-band setup-message from the relay. Decrypts with
    /// `session.encryptionKeyHex`. Polls with backoff up to `timeout`.
    /// Used by the SecureVault peer device to wait for round-2 prep.
    func pollSetupMessage(
        session: KeysignSessionInfo,
        messageID: String,
        timeout: TimeInterval
    ) async throws -> Data {
        guard let baseURL = URL(string: session.serverAddr) else {
            throw KeysignSessionServiceError.startSessionFailed(statusCode: -1)
        }
        let httpClient = HTTPClient()
        let started = Date()
        repeat {
            do {
                let response = try await httpClient.request(TssRelayAPI(
                    baseURL: baseURL,
                    endpoint: .downloadSetupMessage(
                        sessionID: session.sessionId,
                        messageID: messageID,
                        additionalHeader: nil
                    )
                ))
                guard let encryptedString = String(data: response.data, encoding: .utf8) else {
                    throw KeysignSessionServiceError.invalidSetupMessageBody
                }
                guard let plaintext = encryptedString.aesDecryptGCM(key: session.encryptionKeyHex),
                      let plainData = plaintext.data(using: .utf8) else {
                    throw KeysignSessionServiceError.setupMessageDecryptFailed
                }
                return plainData
            } catch let HTTPError.statusCode(code, _) where code == 404 {
                // Not yet available — back off and retry.
                if Date().timeIntervalSince(started) > timeout {
                    throw KeysignSessionServiceError.setupMessageTimeout
                }
                try await Task.sleep(for: .seconds(1))
            } catch let HTTPError.statusCode(code, _) {
                throw KeysignSessionServiceError.startSessionFailed(statusCode: code)
            }
        } while !Task.isCancelled
        throw CancellationError()
    }

    // MARK: - Kickoff awaiting (peer side)

    /// Polls `GET {serverAddr}/start/{sessionID}` until the initiator
    /// has POSTed the participant list (HTTP 200 + non-empty body).
    /// Returns the participants. Used by the peer device to learn the
    /// committee after the initiator has kicked off the keysign.
    func awaitKeysignStart(session: KeysignSessionInfo, timeout: TimeInterval) async throws -> [String] {
        guard let baseURL = URL(string: session.serverAddr) else {
            throw KeysignSessionServiceError.kickoffFailed(statusCode: -1)
        }
        let started = Date()
        while !Task.isCancelled {
            if Date().timeIntervalSince(started) > timeout {
                throw KeysignSessionServiceError.kickoffTimeout
            }
            do {
                let response = try await httpClient.request(
                    RelayServerAPI(
                        baseURL: baseURL,
                        endpoint: .pollSessionStart(sessionID: session.sessionId)
                    )
                )
                if response.response.statusCode == 200, !response.data.isEmpty {
                    return try JSONDecoder().decode([String].self, from: response.data)
                }
            } catch {
                logger.debug("awaitKeysignStart poll error (will retry): \(error.localizedDescription)")
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw CancellationError()
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
