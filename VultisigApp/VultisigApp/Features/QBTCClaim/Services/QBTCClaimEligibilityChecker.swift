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
//  parallel kill-switch + UTXO fetch, the confirmation gate (hide UTXOs
//  below `MinUtxoConfirmationBlocks`), then `filterClaimable` to drop
//  already-claimed / not-indexed entries. Any failure that would prevent
//  a real claim from succeeding (kill-switch closed, unsupported address,
//  network error) collapses to `.ineligible` so we don't lie to the user.
//
//  **Caching:** the last `.eligible` outcome is persisted to UserDefaults
//  keyed by (vaultPubKeyECDSA, BTC address). On subsequent entries to the
//  chain-detail screen the checker hydrates `state` from cache *before*
//  firing the network refresh so the banner / Claim button render
//  immediately — no flicker between idle and eligible. Transient network
//  failures leave the cached state visible; only deterministic outcomes
//  (no UTXOs, kill-switch closed, unsupported address) clear the cache.
//

import Combine
import Foundation
import OSLog

/// Thin abstractions over `BlockchairService` + `QBTCChainService` so
/// the eligibility logic can be unit-tested without network access. The
/// concrete services conform via extension elsewhere in this file.
protocol BlockchairServiceClaimable: Sendable {
    func fetchQBTCClaimableUtxos(bitcoinCoin: CoinMeta, address: String) async throws -> QBTCClaimableUtxosResult
}

protocol QBTCChainServiceClaimable: Sendable {
    func filterClaimable(_ utxos: [ClaimableUtxo]) async -> [ClaimableUtxo]
    func isClaimWithProofDisabled() async throws -> Bool
    func minUtxoConfirmationBlocks() async throws -> UInt32
    func filterSufficientlyConfirmed(
        _ utxos: [ClaimableUtxo],
        btcTipHeight: UInt32?,
        minConfirmations: UInt32
    ) -> [ClaimableUtxo]
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
    private let cacheStore: UserDefaults
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
        chainService: QBTCChainServiceClaimable = QBTCChainService(),
        cacheStore: UserDefaults = .standard
    ) {
        self.blockchairService = blockchairService
        self.chainService = chainService
        self.cacheStore = cacheStore
    }

    /// Runs the eligibility pipeline against `btcCoin.address`. Idempotent
    /// across overlapping calls: the second await joins the first task.
    /// On entry, hydrates `state` from the persisted cache (if any) so the
    /// UI flashes the right thing immediately — the network refresh fires
    /// in the background and updates state when it lands.
    ///
    /// - Parameters:
    ///   - btcCoin: The BTC source coin. `address` is used as part of the
    ///     cache key + the blockchair lookup target.
    ///   - vaultPubKeyECDSA: Vault identifier scoping the cache so two
    ///     vaults with the same BTC address (rare but possible) can't
    ///     contaminate each other's cached state.
    func check(btcCoin: Coin, vaultPubKeyECDSA: String) async {
        if let inFlightTask {
            await inFlightTask.value
            return
        }

        let address = btcCoin.address
        let cacheKey = Self.cacheKey(vaultPubKeyECDSA: vaultPubKeyECDSA, address: address)

        // Hydrate from cache so the banner / button appears on the very
        // first frame the screen renders. `loadCache` returns nil on
        // cold-start or after a definitive ineligible outcome — in that
        // case fall through to .loading until the pipeline resolves.
        let hadCachedEligible: Bool
        if let cached = loadCache(key: cacheKey) {
            state = .eligible(count: cached.count, totalSats: cached.totalSats)
            hadCachedEligible = true
        } else {
            state = .loading
            hadCachedEligible = false
        }

        lastCheckedAddress = address
        let coinMeta = btcCoin.toCoinMeta()

        let task = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.runPipeline(coinMeta: coinMeta, address: address)
            self.applyOutcome(outcome, cacheKey: cacheKey, hadCachedEligible: hadCachedEligible)
        }
        inFlightTask = task
        await task.value
        inFlightTask = nil
    }

    // MARK: - Pipeline

    /// Possible outcomes of a single eligibility run. Splits transient
    /// errors from deterministic ineligibility so we know whether to
    /// clear the cache.
    private enum PipelineOutcome {
        case eligible(count: Int, totalSats: UInt64)
        /// Deterministic "nothing to claim" — kill-switch closed, all
        /// UTXOs already claimed, no UTXOs at all, unsupported address.
        /// Clears the persisted cache.
        case ineligible
        /// Transient pipeline failure (network error). Cache is preserved
        /// so the user keeps seeing the last known-good state.
        case error
    }

    private func runPipeline(coinMeta: CoinMeta, address: String) async -> PipelineOutcome {
        // Address-type guard up front so we don't burn network calls on
        // P2TR / testnet — the claim flow rejects those at the same stage.
        do {
            _ = try BtcAddressType.detect(address)
        } catch {
            logger.debug("Address \(address, privacy: .public) rejected by BtcAddressType.detect: \(error.localizedDescription, privacy: .public)")
            return .ineligible
        }

        async let killSwitchTask = chainService.isClaimWithProofDisabled()
        async let utxosTask = blockchairService.fetchQBTCClaimableUtxos(
            bitcoinCoin: coinMeta,
            address: address
        )

        let killSwitchDisabled: Bool
        let fetched: QBTCClaimableUtxosResult
        do {
            killSwitchDisabled = try await killSwitchTask
            fetched = try await utxosTask
        } catch {
            logger.warning("Eligibility pipeline failed for \(address, privacy: .public): \(error.localizedDescription, privacy: .public) — treating as transient error")
            return .error
        }

        if killSwitchDisabled {
            return .ineligible
        }

        // Same confirmation gate as the claim screen so the banner / Claim
        // button don't promise UTXOs the chain would reject as
        // under-confirmed. Fail-open on a param-fetch error.
        let confirmed = await confirmationGated(fetched.utxos, btcTipHeight: fetched.btcTipHeight)

        let filtered = await chainService.filterClaimable(confirmed)
        if filtered.isEmpty {
            return .ineligible
        }

        let totalSats = filtered.reduce(UInt64(0)) { $0 + $1.amount }
        return .eligible(count: filtered.count, totalSats: totalSats)
    }

    /// Applies the confirmation gate. Fetches `MinUtxoConfirmationBlocks` and
    /// drops under-confirmed UTXOs; on a param-fetch failure returns the input
    /// unchanged (fail-open, consistent with `filterClaimable`).
    private func confirmationGated(
        _ utxos: [ClaimableUtxo],
        btcTipHeight: UInt32?
    ) async -> [ClaimableUtxo] {
        guard !utxos.isEmpty else { return utxos }
        do {
            let minConfirmations = try await chainService.minUtxoConfirmationBlocks()
            return chainService.filterSufficientlyConfirmed(
                utxos,
                btcTipHeight: btcTipHeight,
                minConfirmations: minConfirmations
            )
        } catch {
            logger.warning("MinUtxoConfirmationBlocks fetch failed — skipping confirmation gate (fail-open): \(error.localizedDescription)")
            return utxos
        }
    }

    private func applyOutcome(_ outcome: PipelineOutcome, cacheKey: String, hadCachedEligible: Bool) {
        switch outcome {
        case let .eligible(count, totalSats):
            saveCache(key: cacheKey, count: count, totalSats: totalSats)
            state = .eligible(count: count, totalSats: totalSats)
        case .ineligible:
            clearCache(key: cacheKey)
            state = .ineligible
        case .error:
            // Transient network error. If we had a cached eligible result,
            // keep it on screen so the banner doesn't disappear because of
            // a hiccup. Otherwise fall back to ineligible so the UI doesn't
            // get stuck on .loading.
            if !hadCachedEligible {
                state = .ineligible
            }
        }
    }

    // MARK: - Cache

    /// Persisted shape — kept narrow on purpose. We don't cache the UTXO
    /// list itself; only the rendering-relevant rollup. The fresh pipeline
    /// run rebuilds the full set, and the claim screen always re-fetches.
    private struct CachedEligibility: Codable {
        let count: Int
        let totalSats: UInt64
        let checkedAt: Date
    }

    private static let cacheKeyPrefix = "qbtcClaimEligibility"

    private static func cacheKey(vaultPubKeyECDSA: String, address: String) -> String {
        "\(cacheKeyPrefix).\(vaultPubKeyECDSA).\(address)"
    }

    private func loadCache(key: String) -> CachedEligibility? {
        guard let data = cacheStore.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CachedEligibility.self, from: data)
    }

    private func saveCache(key: String, count: Int, totalSats: UInt64) {
        let entry = CachedEligibility(count: count, totalSats: totalSats, checkedAt: Date())
        guard let data = try? JSONEncoder().encode(entry) else { return }
        cacheStore.set(data, forKey: key)
    }

    private func clearCache(key: String) {
        cacheStore.removeObject(forKey: key)
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
