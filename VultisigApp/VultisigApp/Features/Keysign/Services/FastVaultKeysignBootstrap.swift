//
//  FastVaultKeysignBootstrap.swift
//  VultisigApp
//
//  Off-screen relay-session bootstrap for the fast-vault signing path.
//  A fast vault's `KeysignInput` can't be built up front: every field is
//  known except `keysignCommittee`, which only materializes once the
//  Vultiserver joins the relay session. This helper runs the same
//  wake -> await -> kickoff sequence the pairing screen used to run
//  (and that `QBTCClaimRoundRunner` runs), then assembles the finished
//  `KeysignInput`. It lets Send / Swap / FunctionCall / CustomMessage
//  route straight from Verify into Keysign without mounting the pairing
//  screen. Built on the view-free `KeysignSessionService`.
//

import Foundation
import OSLog

/// Session-bootstrap surface the fast-vault helper depends on. The
/// production conformer is `KeysignSessionService`; tests inject a mock
/// to assert the call ordering + `KeysignInput` assembly without
/// touching the relay.
@MainActor
protocol FastVaultKeysignSessionProviding {
    func newSession(vault: Vault, serviceName: String?) throws -> KeysignSessionInfo
    func registerAsParticipant(session: KeysignSessionInfo) async throws
    func wakeFastVaultServer(
        publicKeyEcdsa: String,
        keysignMessages: [String],
        session: KeysignSessionInfo,
        derivePath: String,
        isECDSA: Bool,
        vaultPassword: String,
        chain: String,
        isMldsa: Bool
    ) async throws
    func awaitFastVaultPeer(
        discovery: ParticipantDiscovery,
        session: KeysignSessionInfo,
        timeout: TimeInterval
    ) async throws -> [String]
    func kickoffCommittee(session: KeysignSessionInfo, participants: [String]) async throws
}

extension KeysignSessionService: FastVaultKeysignSessionProviding {}

enum FastVaultKeysignBootstrapError: LocalizedError {
    case missingSigningCoin
    case noMessagesToSign
    case missingPayload

    var errorDescription: String? {
        switch self {
        case .missingSigningCoin:
            return "Could not resolve the signing coin for this vault."
        case .noMessagesToSign:
            return "No messages to sign."
        case .missingPayload:
            return "No keysign payload or custom message to sign."
        }
    }
}

/// Runs the fast-vault relay-session bootstrap and returns a ready-to-use
/// `KeysignInput`. Mirrors the fast branch of
/// `KeysignDiscoveryViewModel.setData` (Solana blockhash refresh, message
/// generation, wake) and `QBTCClaimRoundRunner.runBtcRound` (register ->
/// wake -> await -> kickoff), consolidating the three former copies of
/// that logic onto one path.
@MainActor
struct FastVaultKeysignBootstrap {
    /// Cap on how long to wait for Vultiserver to register as a peer
    /// after the wake POST. It typically joins within a few seconds; the
    /// cap is a safety net. Matches `QBTCClaimRoundRunner`.
    static let fastVaultPeerWaitSeconds: TimeInterval = 60

    private let sessionService: FastVaultKeysignSessionProviding
    private let logger = Logger(subsystem: "com.vultisig.app", category: "fast-vault-keysign-bootstrap")

    init(sessionService: FastVaultKeysignSessionProviding = KeysignSessionService()) {
        self.sessionService = sessionService
    }

    /// Provisions a session, wakes Vultiserver, awaits its join, kicks off
    /// the committee, and assembles the `KeysignInput`. Throws on any
    /// bootstrap failure (wrong password surfaces as a peer timeout).
    func makeKeysignInput(
        vault: Vault,
        keysignPayload: KeysignPayload?,
        customMessagePayload: CustomMessagePayload?,
        fastVaultPassword: String
    ) async throws -> KeysignInput {
        let session = try sessionService.newSession(vault: vault, serviceName: nil)

        // Resolve the signing coin + pre-signed messages. Mirrors the
        // coin/message resolution in `KeysignDiscoveryViewModel.setData`.
        let coin: Coin
        var finalPayload = keysignPayload
        let keysignMessages: [String]

        if let payload = keysignPayload {
            var workingPayload = payload
            // Refresh the Solana blockhash BEFORE generating messages so
            // this device and the Vultiserver share the same fresh hash.
            if payload.coin.chain == .solana {
                workingPayload = try await BlockChainService.shared.refreshSolanaBlockhash(for: payload)
                logger.info("Refreshed Solana blockhash before generating keysign messages")
            }
            finalPayload = workingPayload
            keysignMessages = try KeysignMessageFactory(payload: workingPayload).getKeysignMessages().sorted()
            coin = workingPayload.coin
        } else if let customMessagePayload {
            keysignMessages = customMessagePayload.keysignMessages
            guard let resolved = vault.nativeCoin(for: Chain(name: customMessagePayload.chain) ?? .ethereum) else {
                throw FastVaultKeysignBootstrapError.missingSigningCoin
            }
            coin = resolved
        } else {
            throw FastVaultKeysignBootstrapError.missingPayload
        }

        guard !keysignMessages.isEmpty else {
            throw FastVaultKeysignBootstrapError.noMessagesToSign
        }

        // Register on the relay BEFORE waking Vultiserver — without this
        // POST the relay may never queue the server's outbound MPC
        // messages to this device. Mirrors `QBTCClaimRoundRunner`.
        try await sessionService.registerAsParticipant(session: session)

        try await sessionService.wakeFastVaultServer(
            publicKeyEcdsa: vault.pubKeyECDSA,
            keysignMessages: keysignMessages,
            session: session,
            derivePath: coin.coinType.derivationPath(),
            isECDSA: coin.chain.isECDSA,
            vaultPassword: fastVaultPassword,
            chain: coin.chain.name,
            isMldsa: coin.chain.signingKeyType == .MLDSA
        )

        let participants = try await sessionService.awaitFastVaultPeer(
            discovery: ParticipantDiscovery(),
            session: session,
            timeout: Self.fastVaultPeerWaitSeconds
        )

        try await sessionService.kickoffCommittee(session: session, participants: participants)

        // Derive the signing key type from the resolved coin so a
        // custom message on a non-ECDSA chain (which carries no
        // `keysignPayload`) still matches the key type the server was
        // woken for. For the payload path this equals
        // `keysignPayload.coin.chain.signingKeyType`.
        let keysignType: KeyType = coin.chain.signingKeyType
        return KeysignInput(
            vault: vault,
            keysignCommittee: participants,
            mediatorURL: session.serverAddr,
            sessionID: session.sessionId,
            keysignType: keysignType,
            messsageToSign: keysignMessages,
            keysignPayload: finalPayload,
            customMessagePayload: customMessagePayload,
            encryptionKeyHex: session.encryptionKeyHex,
            isInitiateDevice: true
        )
    }
}
