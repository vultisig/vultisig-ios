//
//  QBTCClaimViewModel.swift
//  VultisigApp
//
//  Drives the QBTC claim selection screen: kill-switch + FastVault
//  gating, UTXO loading, selection state, and password collection.
//  After the user confirms, the screen reads `pendingPairContext`
//  (SecureVault) or `pendingKeysignContext` (FastVault) and pushes the
//  corresponding `QBTCClaimRoute` — pair / keysign / done are all
//  router-managed screens. Selection lives on the ViewModel so it
//  survives a failed run and the user can retry from this screen.
//

import Foundation
import OSLog
import SwiftUI

/// Top-level state for the selection screen. Drives which sub-view
/// renders. The initial gate-checks phase is surfaced via `isLoading` +
/// the shared `withLoading` modifier rather than a dedicated `.loading`
/// case.
enum QBTCClaimScreenState: Hashable {
    /// User cannot claim. Surface the reason in a banner; CTA disabled.
    case blocked(reason: QBTCClaimBlockedReason)
    /// Selectable UTXOs available — user picks then confirms.
    case selecting
}

enum QBTCClaimBlockedReason: Hashable {
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

/// Inputs the SecureVault pair screen needs after the VM has
/// provisioned the relay session and built the QR payload.
struct QBTCClaimPairContext: Equatable {
    let keysignPayload: KeysignPayload
    let session: KeysignSessionInfo
    let btcCoin: Coin
    let qbtcCoin: Coin
    let selectedUtxos: [ClaimableUtxo]
}

/// Inputs the FastVault keysign screen needs after the user has
/// supplied their password.
struct QBTCClaimKeysignContext: Equatable {
    let btcCoin: Coin
    let qbtcCoin: Coin
    let selectedUtxos: [ClaimableUtxo]
    let fastVaultPassword: String
}

@MainActor
final class QBTCClaimViewModel: ObservableObject {
    @Published private(set) var state: QBTCClaimScreenState = .selecting
    /// Drives the `withLoading` overlay on the screen while the gate
    /// checks + UTXO fetch run. Starts `true` so the spinner is visible
    /// immediately; the `load()` task flips it off on every exit path.
    @Published var isLoading: Bool = true
    @Published private(set) var utxos: [ClaimableUtxo] = []
    /// User's selection. Surviving across failed runs is the contract.
    @Published var selectedIds: Set<QBTCClaimUtxoId> = []
    /// User-visible error message banner shown on the selection screen
    /// (most recent failure from a previous run, or pairing-setup
    /// failure). Cleared on retry.
    @Published var lastClaimError: String?
    /// Bound to the FastVault password modal.
    @Published var fastVaultPassword: String = ""
    @Published var isPasswordSheetPresented: Bool = false

    /// Set when the user confirms a SecureVault claim and the VM has
    /// successfully provisioned a relay session. The screen observes
    /// this and pushes `QBTCClaimRoute.pair`. Cleared by the screen
    /// after navigation so the same value doesn't re-fire.
    @Published var pendingPairContext: QBTCClaimPairContext?
    /// Set when the user submits their FastVault password. The screen
    /// pushes `QBTCClaimRoute.keysign` (with `session: nil`).
    @Published var pendingKeysignContext: QBTCClaimKeysignContext?

    let vault: Vault

    private let chainService: QBTCChainService
    private let blockchairService: BlockchairService
    private let sessionService: KeysignSessionService
    private let logger = Logger(subsystem: "com.vultisig.app", category: "qbtc-claim-vm")

    init(
        vault: Vault,
        chainService: QBTCChainService = QBTCChainService(),
        blockchairService: BlockchairService = .shared,
        sessionService: KeysignSessionService = KeysignSessionService()
    ) {
        self.vault = vault
        self.chainService = chainService
        self.blockchairService = blockchairService
        self.sessionService = sessionService
    }

    // MARK: - Computed

    var btcCoin: Coin? { vault.nativeCoin(for: .bitcoin) }
    var qbtcCoin: Coin? { vault.nativeCoin(for: .qbtc) }

    var totalSatsSelected: UInt64 {
        utxos
            .filter { selectedIds.contains($0.id) }
            .reduce(UInt64(0)) { $0 + $1.amount }
    }

    var totalSatsAll: UInt64 {
        utxos.reduce(UInt64(0)) { $0 + $1.amount }
    }

    /// Caps the "Select all" affordance at `maxClaimUtxos`. If the vault
    /// has more UTXOs than the per-claim limit, "all" means "as many as
    /// we can include in one claim".
    var selectAllCount: Int {
        min(utxos.count, QBTCClaimConfig.maxClaimUtxos)
    }

    var isAllSelected: Bool {
        !utxos.isEmpty && selectedIds.count == selectAllCount
    }

    var canConfirm: Bool {
        !selectedIds.isEmpty && selectedIds.count <= QBTCClaimConfig.maxClaimUtxos
    }

    /// Dynamic CTA title: "Claim All" when the current selection covers
    /// every includable UTXO, otherwise "Claim X of Y".
    var confirmTitle: String {
        if isAllSelected {
            return "qbtcClaimCtaAll".localized
        }
        return String(
            format: "qbtcClaimCtaPartial".localized,
            selectedIds.count,
            utxos.count
        )
    }

    func toggleSelectAll() {
        if isAllSelected {
            selectedIds.removeAll()
            return
        }
        let limit = QBTCClaimConfig.maxClaimUtxos
        selectedIds = Set(utxos.prefix(limit).map { $0.id })
    }

    // MARK: - Lifecycle

    /// Runs the gate checks + UTXO fetch in parallel. Idempotent — safe
    /// to call multiple times. `isLoading` drives the shared
    /// `withLoading` overlay during the fetch; `state` settles on
    /// `.blocked / .selecting` once the gate decision is made.
    func load() async {
        await MainActor.run {
            isLoading = true
            lastClaimError = nil
        }
        defer { isLoading = false }

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
            // Reconcile selection against the freshly fetched set so a
            // reload that drops UTXOs doesn't leave stale ids selected.
            let validIds = Set(fetchedUtxos.map(\.id))
            selectedIds.formIntersection(validIds)
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
    /// vault type — FastVault collects the password first; SecureVault
    /// provisions a relay session and signals the screen to push the
    /// pair route.
    func confirmTapped() {
        guard canConfirm else { return }
        lastClaimError = nil
        if vault.isFastVault {
            isPasswordSheetPresented = true
        } else {
            Task { await prepareSecureVaultPair() }
        }
    }

    /// FastVault — called after the password sheet's Submit. Validates
    /// the password is non-empty and emits a keysign context for the
    /// screen to route on.
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

        pendingKeysignContext = QBTCClaimKeysignContext(
            btcCoin: btcCoin,
            qbtcCoin: qbtcCoin,
            selectedUtxos: selected,
            fastVaultPassword: password
        )
    }

    /// Called when the user dismisses an error banner. Clears local
    /// error state.
    func resetForRetry() {
        fastVaultPassword = ""
        lastClaimError = nil
    }

    // MARK: - SecureVault pair preparation

    /// Provisions a fresh relay session, builds the keysign payload,
    /// registers as the initiating participant, and emits a pair
    /// context. On failure, surfaces the error in the selection
    /// banner so the user can retry.
    private func prepareSecureVaultPair() async {
        guard let btcCoin, let qbtcCoin else { return }
        let selected = utxos.filter { selectedIds.contains($0.id) }
        guard !selected.isEmpty else { return }

        do {
            let session = try sessionService.newSession(vault: vault)
            let payload = makeSecureVaultKeysignPayload(btcCoin: btcCoin)
            try await sessionService.registerAsParticipant(session: session)

            pendingPairContext = QBTCClaimPairContext(
                keysignPayload: payload,
                session: session,
                btcCoin: btcCoin,
                qbtcCoin: qbtcCoin,
                selectedUtxos: selected
            )
        } catch {
            logger.error("SecureVault pairing setup failed: \(error.localizedDescription)")
            lastClaimError = error.localizedDescription
        }
    }

    private func makeSecureVaultKeysignPayload(btcCoin: Coin) -> KeysignPayload {
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
            isQbtcClaim: true,
            skipBroadcast: true,
            signData: nil
        )
    }

    // MARK: - Private

    private func fetchUtxos(btcCoin: Coin) async throws -> [ClaimableUtxo] {
        let blockchairUtxos = try await blockchairService.fetchQBTCClaimableUtxos(
            bitcoinCoin: btcCoin.toCoinMeta(),
            address: btcCoin.address
        )
        // Drop already-claimed (entitled_amount=0) and not-yet-indexed (404)
        // entries before showing them to the user. Fails open on transient
        // chain errors — see `QBTCChainService.filterClaimable`.
        let filtered = await chainService.filterClaimable(blockchairUtxos)
        if filtered.count != blockchairUtxos.count {
            logger.debug("Filtered QBTC UTXOs: blockchair=\(blockchairUtxos.count, privacy: .public) claimable=\(filtered.count, privacy: .public)")
        }
        return filtered
    }

    // MARK: - Snapshot test seeding

    #if DEBUG
    /// Seeds the view model into a deterministic `.selecting` state for
    /// snapshot tests. Sets `isLoading = false` so the `withLoading`
    /// overlay doesn't cover the captured frame.
    func snapshotSeed(utxos: [ClaimableUtxo], selected: Set<QBTCClaimUtxoId>) {
        self.utxos = utxos
        self.selectedIds = selected
        self.state = utxos.isEmpty ? .blocked(reason: .noUtxos) : .selecting
        self.isLoading = false
    }
    #endif
}
