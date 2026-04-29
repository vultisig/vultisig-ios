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

/// Top-level state for the claim screen. Drives which sub-view renders.
enum QBTCClaimScreenState: Equatable {
    /// Initial gate checks running (kill-switch + FastVault + UTXO load).
    case loading
    /// User cannot claim. Surface the reason in a banner; CTA disabled.
    case blocked(reason: QBTCClaimBlockedReason)
    /// Selectable UTXOs available — user picks then confirms.
    case selecting
    /// Orchestrator is running. The orchestrator's `phase` drives the
    /// inner content; selection is preserved on the ViewModel.
    case claiming
    /// Final state on success.
    case done(QBTCClaimRunResult)
}

enum QBTCClaimBlockedReason: Equatable {
    /// `vault.isFastVault == false`. v1 supports FastVault only;
    /// SecureVault is on the roadmap.
    case secureVaultUnsupported
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

    let vault: Vault
    let orchestrator: QBTCClaimOrchestrator

    private let chainService: QBTCChainService
    private let blockchairService: BlockchairService
    private let logger = Logger(subsystem: "com.vultisig.app", category: "qbtc-claim-vm")
    private var cancellables: Set<AnyCancellable> = []

    init(
        vault: Vault,
        orchestrator: QBTCClaimOrchestrator? = nil,
        chainService: QBTCChainService = QBTCChainService(),
        blockchairService: BlockchairService = .shared
    ) {
        self.vault = vault
        self.orchestrator = orchestrator ?? QBTCClaimOrchestrator.makeProduction()
        self.chainService = chainService
        self.blockchairService = blockchairService

        // Mirror the orchestrator's phase into our screen state so the
        // view re-renders as the run progresses. Done state replaces
        // .claiming; failed surfaces a banner and returns to .selecting.
        self.orchestrator.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                self?.applyOrchestratorPhase(phase)
            }
            .store(in: &cancellables)
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

        guard vault.isFastVault else {
            state = .blocked(reason: .secureVaultUnsupported)
            return
        }
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

    /// Triggered when the user taps the Confirm button. Opens the
    /// FastVault password sheet. Submission of the sheet calls
    /// `startClaim()`.
    func openPasswordSheet() {
        guard canConfirm else { return }
        lastClaimError = nil
        isPasswordSheetPresented = true
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
        orchestrator.reset()
        state = .selecting
    }

    // MARK: - Private

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
            state = .done(result)
        case .failed(let message):
            lastClaimError = message
            state = .selecting
        }
    }
}
