//
//  QBTCClaimEligibilityChecker.swift
//  VultisigApp
//
//  Decides whether the QBTC promo banner (on BTC chain detail) and the
//  Claim button (on QBTC chain detail) should be visible. Both surfaces
//  share the same predicate — "the user has at least one BTC UTXO the
//  chain will accept as a QBTC claim" — so the gate lives in one place
//  instead of being duplicated across the two chain-detail screens.
//
//  The pipeline mirrors `QBTCClaimViewModel.load()`: address-type guard,
//  parallel kill-switch + UTXO fetch, then `filterClaimable` to drop
//  already-claimed / not-indexed entries. Any failure that would prevent
//  a real claim from succeeding (kill-switch closed, unsupported address,
//  network error) collapses to `.ineligible` so we don't lie to the user.
//

import Combine
import Foundation
import OSLog

/// Thin abstractions over `BlockchairService` + `QBTCChainService` so
/// the eligibility logic can be unit-tested without network access. The
/// concrete services conform via extension elsewhere in this file.
protocol BlockchairServiceClaimable: Sendable {
    func fetchQBTCClaimableUtxos(bitcoinCoin: CoinMeta, address: String) async throws -> [ClaimableUtxo]
}

protocol QBTCChainServiceClaimable: Sendable {
    func filterClaimable(_ utxos: [ClaimableUtxo]) async -> [ClaimableUtxo]
    func isClaimWithProofDisabled() async throws -> Bool
}

@MainActor
final class QBTCClaimEligibilityChecker: ObservableObject {

    enum State: Equatable {
        /// Not yet checked. Banner / button hidden — avoids flicker before
        /// the first fetch resolves.
        case idle
        /// First check in flight. UI keeps the banner hidden.
        case loading
        /// At least one claimable UTXO. UI surfaces the banner / button.
        case eligible(count: Int, totalSats: UInt64)
        /// Definitive "nothing to claim" outcome: no UTXOs, all already
        /// claimed, kill-switch closed, unsupported address, or any
        /// network error along the pipeline.
        case ineligible
    }

    @Published private(set) var state: State = .idle

    /// Convenience surface for views — true iff `state == .eligible`.
    var hasClaimableUtxos: Bool {
        if case .eligible = state { return true }
        return false
    }

    private let blockchairService: BlockchairServiceClaimable
    private let chainService: QBTCChainServiceClaimable
    private let logger = Logger(subsystem: "com.vultisig.app", category: "qbtc-eligibility")

    /// Address most recently checked. A subsequent `check()` with a
    /// different address always re-runs; same-address calls also re-run
    /// (the caller decides cadence — pull-to-refresh, onAppear, etc.).
    private var lastCheckedAddress: String?
    /// Guard so two near-simultaneous `check()` calls don't fire two
    /// network round-trips. The second caller awaits the in-flight task.
    private var inFlightTask: Task<Void, Never>?

    init(
        blockchairService: BlockchairServiceClaimable = BlockchairService.shared,
        chainService: QBTCChainServiceClaimable = QBTCChainService()
    ) {
        self.blockchairService = blockchairService
        self.chainService = chainService
    }

    /// Runs the eligibility pipeline against `btcCoin.address`. Idempotent
    /// across overlapping calls: the second await joins the first task.
    /// Cold-cached: each invocation hits the network again — callers
    /// decide the cadence.
    func check(btcCoin: Coin) async {
        if let inFlightTask {
            await inFlightTask.value
            return
        }

        let address = btcCoin.address
        let coinMeta = btcCoin.toCoinMeta()
        lastCheckedAddress = address
        state = .loading

        let task = Task { [weak self] in
            guard let self else { return }
            await self.runPipeline(coinMeta: coinMeta, address: address)
        }
        inFlightTask = task
        await task.value
        inFlightTask = nil
    }

    // MARK: - Pipeline

    private func runPipeline(coinMeta: CoinMeta, address: String) async {
        // Address-type guard up front so we don't burn network calls on
        // P2TR / testnet — the claim flow rejects those at the same stage.
        do {
            _ = try BtcAddressType.detect(address)
        } catch {
            logger.debug("Address \(address, privacy: .public) rejected by BtcAddressType.detect: \(error.localizedDescription, privacy: .public)")
            state = .ineligible
            return
        }

        async let killSwitchTask = chainService.isClaimWithProofDisabled()
        async let utxosTask = blockchairService.fetchQBTCClaimableUtxos(
            bitcoinCoin: coinMeta,
            address: address
        )

        let killSwitchDisabled: Bool
        let rawUtxos: [ClaimableUtxo]
        do {
            killSwitchDisabled = try await killSwitchTask
            rawUtxos = try await utxosTask
        } catch {
            logger.warning("Eligibility pipeline failed for \(address, privacy: .public): \(error.localizedDescription, privacy: .public) — treating as ineligible")
            state = .ineligible
            return
        }

        if killSwitchDisabled {
            state = .ineligible
            return
        }

        let filtered = await chainService.filterClaimable(rawUtxos)
        if filtered.isEmpty {
            state = .ineligible
            return
        }

        let totalSats = filtered.reduce(UInt64(0)) { $0 + $1.amount }
        state = .eligible(count: filtered.count, totalSats: totalSats)
    }

    // MARK: - Snapshot test seeding

    #if DEBUG
    /// Seeds the checker into a deterministic state for snapshot tests.
    /// Production code never invokes this.
    func snapshotSeed(state: State) {
        self.state = state
    }
    #endif
}

// MARK: - Concrete conformances

extension BlockchairService: BlockchairServiceClaimable {}
extension QBTCChainService: QBTCChainServiceClaimable {}
