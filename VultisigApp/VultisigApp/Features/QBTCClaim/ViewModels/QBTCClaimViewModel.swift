//
//  QBTCClaimViewModel.swift
//  VultisigApp
//
//  Drives the QBTC claim screen: kill-switch + FastVault gating, UTXO
//  loading, selection state, password collection, and orchestrator
//  invocation. Selection lives on the ViewModel (NOT on the orchestrator)
//  so it survives a failed run — the user can correct and retry without
//  re-picking UTXOs.
//

import Combine
import Foundation
import OSLog
import SwiftUI

/// Top-level state for the claim screen. Drives which sub-view renders.
enum QBTCClaimScreenState: Equatable {
    /// Initial gate checks running (kill-switch + FastVault + UTXO load).
    case loading
    /// User cannot claim. Surface the reason in a banner; CTA disabled.
    case blocked(reason: QBTCClaimBlockedReason)
    /// Selectable UTXOs available — user picks then confirms.
    case selecting
    /// SecureVault flow only — the QR is on screen and we're polling
    /// `ParticipantDiscovery` for the peer device to join the relay
    /// session. Transitions to `.claiming` once the peer is found.
    case awaitingPeer
    /// Orchestrator is running. The orchestrator's `phase` drives the
    /// inner content; selection is preserved on the ViewModel.
    case claiming
    /// Final state on success.
    case done(QBTCClaimRunResult)
}

enum QBTCClaimBlockedReason: Equatable {
    /// Chain returned `ClaimWithProofDisabled > 0`. Or query failed —
    /// fail-closed.
    case killSwitchClosed
    /// The vault is missing a coin we need (BTC or QBTC).
    case missingCoin(chainName: String)
    /// Claim flow rejected the BTC address (e.g. P2TR, testnet).
    case unsupportedBtcAddress(detail: String)
    /// `getClaimableUtxos` failed.
    case utxoFetchFailed(message: String)
    /// Address has no claimable UTXOs.
    case noUtxos
}

/// Identifier used for selection-state Set lookup.
struct QBTCClaimUtxoId: Hashable {
    let txid: String
    let vout: UInt32
}

extension ClaimableUtxo {
    var id: QBTCClaimUtxoId { QBTCClaimUtxoId(txid: txid, vout: vout) }
}

@MainActor
final class QBTCClaimViewModel: ObservableObject {
    @Published private(set) var state: QBTCClaimScreenState = .loading
    @Published private(set) var utxos: [ClaimableUtxo] = []
    /// User's selection. Surviving across failed runs is the contract:
    /// the screen does NOT clear this on `.failed`.
    @Published var selectedIds: Set<QBTCClaimUtxoId> = []
    /// User-visible error message banner shown on the selection screen
    /// (the most recent failure from a claim run). Cleared on retry.
    @Published var lastClaimError: String?
    /// Bound to the FastVault password modal.
    @Published var fastVaultPassword: String = ""
    @Published var isPasswordSheetPresented: Bool = false

    /// SecureVault pairing — the QR string the peer device scans.
    @Published private(set) var pairingQrCodeData: String?
    /// SecureVault pairing — rendered QR image.
    @Published private(set) var pairingQrImage: Image?
    /// SecureVault pairing — peers observed on the round-1 relay session.
    @Published private(set) var observedPeers: [String] = []

    let vault: Vault
    @Published private(set) var orchestrator: QBTCClaimOrchestrator

    private let chainService: QBTCChainService
    private let blockchairService: BlockchairService
    private let sessionService: KeysignSessionService
    private let logger = Logger(subsystem: "com.vultisig.app", category: "qbtc-claim-vm")
    private var cancellables: Set<AnyCancellable> = []

    /// SecureVault-only — set after `startSecureVaultPair()` provisions
    /// the base session. Per-round sessions derive `-0` / `-1` suffixes.
    private var secureVaultBaseSession: KeysignSessionInfo?
    /// Holds onto the discovery instance so its `$peersFound` stream
    /// keeps publishing while the QR is on screen.
    private var participantDiscovery: ParticipantDiscovery?

    init(
        vault: Vault,
        orchestrator: QBTCClaimOrchestrator? = nil,
        chainService: QBTCChainService = QBTCChainService(),
        blockchairService: BlockchairService = .shared,
        sessionService: KeysignSessionService = KeysignSessionService()
    ) {
        self.vault = vault
        self.orchestrator = orchestrator ?? QBTCClaimOrchestrator.makeFastVault()
        self.chainService = chainService
        self.blockchairService = blockchairService
        self.sessionService = sessionService

        bindOrchestratorPhase()
    }

    // MARK: - Computed

    var btcCoin: Coin? { vault.nativeCoin(for: .bitcoin) }
    var qbtcCoin: Coin? { vault.nativeCoin(for: .qbtc) }

    var totalSatsSelected: UInt64 {
        utxos
            .filter { selectedIds.contains($0.id) }
            .reduce(UInt64(0)) { $0 + $1.amount }
    }

    var canConfirm: Bool {
        !selectedIds.isEmpty && selectedIds.count <= QBTCClaimConfig.maxClaimUtxos
    }

    // MARK: - Lifecycle

    /// Runs the gate checks + UTXO fetch in parallel. Idempotent — safe
    /// to call multiple times (e.g., on screen re-appear).
    func load() async {
        state = .loading
        lastClaimError = nil

        guard let btcCoin else {
            state = .blocked(reason: .missingCoin(chainName: "Bitcoin"))
            return
        }
        guard qbtcCoin != nil else {
            state = .blocked(reason: .missingCoin(chainName: "QBTC"))
            return
        }

        // Address-type guard — reject P2TR/testnet now rather than at
        // proof-service time.
        do {
            _ = try BtcAddressType.detect(btcCoin.address)
        } catch {
            state = .blocked(reason: .unsupportedBtcAddress(detail: error.localizedDescription))
            return
        }

        async let killSwitchTask = chainService.isClaimWithProofDisabled()
        async let utxosTask = fetchUtxos(btcCoin: btcCoin)

        do {
            let (disabled, fetchedUtxos) = try await (killSwitchTask, utxosTask)

            if disabled {
                state = .blocked(reason: .killSwitchClosed)
                return
            }

            self.utxos = fetchedUtxos
            if fetchedUtxos.isEmpty {
                state = .blocked(reason: .noUtxos)
            } else {
                state = .selecting
            }
        } catch let error as QBTCChainServiceError {
            // Kill-switch query errors fail-closed.
            state = .blocked(reason: .killSwitchClosed)
            logger.warning("Kill-switch query failed (treating as closed): \(error.localizedDescription)")
        } catch {
            // UTXO fetch error — surface to the user.
            state = .blocked(reason: .utxoFetchFailed(message: error.localizedDescription))
        }
    }

    // MARK: - Selection actions

    func toggle(_ utxo: ClaimableUtxo) {
        if selectedIds.contains(utxo.id) {
            selectedIds.remove(utxo.id)
        } else if selectedIds.count < QBTCClaimConfig.maxClaimUtxos {
            selectedIds.insert(utxo.id)
        }
    }

    /// Triggered when the user taps the Confirm button. Branches by
    /// vault type — FastVault uses Vultiserver (password sheet), and
    /// SecureVault pairs with a peer device via QR.
    func confirmTapped() {
        guard canConfirm else { return }
        lastClaimError = nil
        if vault.isFastVault {
            isPasswordSheetPresented = true
        } else {
            Task { await startSecureVaultPair() }
        }
    }

    func startClaim() {
        let password = fastVaultPassword
        isPasswordSheetPresented = false
        guard !password.isEmpty else {
            lastClaimError = "qbtcClaimEmptyPassword".localized
            return
        }
        guard let btcCoin, let qbtcCoin else { return }

        let selected = utxos.filter { selectedIds.contains($0.id) }
        guard !selected.isEmpty else { return }

        state = .claiming

        let input = QBTCClaimRunInput(
            vault: vault,
            btcCoin: btcCoin,
            qbtcCoin: qbtcCoin,
            utxos: selected,
            fastVaultPassword: password
        )
        Task { [orchestrator] in
            await orchestrator.run(input)
        }
    }

    /// Called when the user dismisses an error banner and wants to
    /// reselect. Clears the password and returns the orchestrator to
    /// idle so a subsequent `startClaim` runs cleanly.
    func resetForRetry() {
        fastVaultPassword = ""
        lastClaimError = nil
        stopSecureVaultPair()
        orchestrator.reset()
        state = .selecting
    }

    // MARK: - SecureVault pairing

    /// Provisions the base relay session, builds the QR payload (BTC
    /// coin + qbtcClaimContext), starts `ParticipantDiscovery` on the
    /// round-1 session, and transitions to `.awaitingPeer`. When the
    /// peer joins, `secureVaultPeerJoined` fires the orchestrator.
    private func startSecureVaultPair() async {
        guard let btcCoin, let qbtcCoin else { return }
        let selected = utxos.filter { selectedIds.contains($0.id) }
        guard !selected.isEmpty else { return }

        do {
            let baseSession = try sessionService.newSession(vault: vault)
            let context = QBTCClaimContext(
                claimerAddress: qbtcCoin.address,
                utxos: selected,
                baseSessionID: baseSession.sessionId
            )
            let payload = makeSecureVaultKeysignPayload(
                btcCoin: btcCoin,
                context: context
            )
            let qrString = try await encodeKeysignQr(
                baseSession: baseSession,
                payload: payload
            )

            // Round-1 session — peer registers here, initiator polls
            // for it via ParticipantDiscovery.
            let round1Session = sessionService.deriveRoundSession(from: baseSession, roundIndex: 0)
            try await sessionService.registerAsParticipant(session: round1Session)

            self.secureVaultBaseSession = baseSession
            self.pairingQrCodeData = qrString
            self.pairingQrImage = Utils.generateQRCodeImage(from: qrString)
            self.state = .awaitingPeer

            // Begin participant discovery on the round-1 session.
            let discovery = ParticipantDiscovery()
            self.participantDiscovery = discovery
            discovery.getParticipants(
                serverAddr: round1Session.serverAddr,
                sessionID: round1Session.sessionId,
                localParty: round1Session.localPartyId
            )
            discovery.$peersFound
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] peers in
                    self?.observedPeers = peers
                    if !peers.isEmpty {
                        self?.secureVaultPeerJoined()
                    }
                }
                .store(in: &cancellables)
        } catch {
            logger.error("SecureVault pairing failed: \(error.localizedDescription)")
            lastClaimError = error.localizedDescription
            state = .selecting
        }
    }

    private func secureVaultPeerJoined() {
        guard state == .awaitingPeer,
              let baseSession = secureVaultBaseSession,
              let btcCoin,
              let qbtcCoin else {
            return
        }
        guard let firstPeer = observedPeers.first else { return }

        // Stop discovery — the orchestrator owns the session from here.
        participantDiscovery?.stop()
        participantDiscovery = nil

        let participants = [baseSession.localPartyId, firstPeer]
        let secureOrchestrator = QBTCClaimOrchestrator.makeSecureVault(
            baseSession: baseSession,
            participants: participants
        )
        self.orchestrator = secureOrchestrator
        bindOrchestratorPhase()

        let selected = utxos.filter { selectedIds.contains($0.id) }
        let input = QBTCClaimRunInput(
            vault: vault,
            btcCoin: btcCoin,
            qbtcCoin: qbtcCoin,
            utxos: selected,
            fastVaultPassword: ""
        )
        state = .claiming
        Task { [secureOrchestrator] in
            await secureOrchestrator.run(input)
        }
    }

    private func stopSecureVaultPair() {
        participantDiscovery?.stop()
        participantDiscovery = nil
        secureVaultBaseSession = nil
        pairingQrCodeData = nil
        pairingQrImage = nil
        observedPeers = []
    }

    private func makeSecureVaultKeysignPayload(
        btcCoin: Coin,
        context: QBTCClaimContext
    ) -> KeysignPayload {
        KeysignPayload(
            coin: btcCoin,
            toAddress: "",
            toAmount: 0,
            chainSpecific: BlockChainSpecific.UTXO(byteFee: 0, sendMaxAmount: false),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: vault.pubKeyECDSA,
            vaultLocalPartyID: vault.localPartyID,
            libType: (vault.libType ?? .DKLS).toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            qbtcClaimContext: context,
            skipBroadcast: true,
            signData: nil
        )
    }

    /// Builds the QR-payload string. If the serialized `KeysignMessage`
    /// exceeds the 2 KB inline threshold (a full 50-UTXO claim does),
    /// the payload is uploaded to the relay and the message carries
    /// only the payload hash. Mirrors `KeysignDiscoveryViewModel`.
    private func encodeKeysignQr(
        baseSession: KeysignSessionInfo,
        payload: KeysignPayload
    ) async throws -> String {
        let message = KeysignMessage(
            sessionID: baseSession.sessionId,
            serviceName: baseSession.serviceName,
            payload: payload,
            customMessagePayload: nil,
            encryptionKeyHex: baseSession.encryptionKeyHex,
            useVultisigRelay: true,
            payloadID: "",
            customPayloadID: ""
        )
        let serialized = try ProtoSerializer.serialize(message)
        let payloadService = PayloadService(serverURL: baseSession.serverAddr)

        let jsonData: String
        if payloadService.shouldUploadToRelay(payload: serialized) {
            let payloadSerialized = try ProtoSerializer.serialize(payload)
            let hash = try await payloadService.uploadPayload(payload: payloadSerialized)
            let messageWithoutPayload = KeysignMessage(
                sessionID: baseSession.sessionId,
                serviceName: baseSession.serviceName,
                payload: nil,
                customMessagePayload: nil,
                encryptionKeyHex: baseSession.encryptionKeyHex,
                useVultisigRelay: true,
                payloadID: hash,
                customPayloadID: ""
            )
            jsonData = try ProtoSerializer.serialize(messageWithoutPayload)
        } else {
            jsonData = serialized
        }
        return "https://vultisig.com?type=SignTransaction&vault=\(vault.pubKeyECDSA)&jsonData=\(jsonData)"
    }

    // MARK: - Private

    private func bindOrchestratorPhase() {
        cancellables.removeAll()
        // Mirror the orchestrator's phase into our screen state so the
        // view re-renders as the run progresses. Done state replaces
        // .claiming; failed surfaces a banner and returns to .selecting.
        orchestrator.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                self?.applyOrchestratorPhase(phase)
            }
            .store(in: &cancellables)
    }

    private func fetchUtxos(btcCoin: Coin) async throws -> [ClaimableUtxo] {
        try await blockchairService.fetchQBTCClaimableUtxos(
            bitcoinCoin: btcCoin.toCoinMeta(),
            address: btcCoin.address
        )
    }

    private func applyOrchestratorPhase(_ phase: QBTCClaimPhase) {
        switch phase {
        case .idle:
            // Orchestrator idle — nothing to mirror. The view model
            // owns its own `state` for the gate / selection / done UI.
            break
        case .signingBTC, .generatingProof, .signingMLDSA, .broadcasting:
            // The screen renders the orchestrator's phase directly via
            // `claimingView(phase:)` — we just need to stay in `.claiming`.
            if state != .claiming {
                state = .claiming
            }
        case .done(let result):
            stopSecureVaultPair()
            state = .done(result)
        case .failed(let message):
            stopSecureVaultPair()
            lastClaimError = message
            state = .selecting
        }
    }
}
