//
//  KaminoEarnViewModel.swift
//  VultisigApp
//
//  Backs the Earn segment on the Solana DeFi tab: one row per curated Kamino
//  vault the user enabled.
//
//  Read-only. Deposit and withdraw are separate flows; nothing here builds,
//  validates or signs a transaction.
//
//  The read model is three sources, none of which is sufficient alone:
//  `/positions` gives shares and nothing else, `metrics.tokensPerShare` turns
//  shares into the underlying token, and `RateProvider` turns that into fiat.
//  `/pnl` supplies the profit-and-loss row.
//
//  Cache-first, like `SolanaStakeDefiViewModel`: the persisted `KaminoPosition`
//  rows paint synchronously before any network call, and a failed read keeps
//  them rather than blanking the user's positions.
//

import Foundation
import OSLog

@MainActor
final class KaminoEarnViewModel: ObservableObject {
    @Published private(set) var rows: [KaminoEarnRow] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?

    private var vault: Vault
    private let service: KaminoServiceProtocol
    private let storage: KaminoPositionStorageService
    private let priceService: CryptoPriceServiceProtocol
    private let logger = Log.defi.viewModel
    /// The refresh currently in flight, if any.
    ///
    /// A new refresh — or a vault switch — cancels it, which is what stops a
    /// slower earlier pass from overwriting a newer result, or from resurrecting
    /// a vault the user just disabled: the enabled set is read when the refresh
    /// starts, so a superseded pass is working from a stale one.
    ///
    /// Cancellation rather than a discard token, because it also stops the work.
    /// The pass is one request per enabled vault plus a rates fetch, and a
    /// superseded one used to run every one of them to completion before its
    /// result was thrown away.
    private var refreshTask: Task<Void, Never>?

    init(
        vault: Vault,
        service: KaminoServiceProtocol = KaminoService(),
        storage: KaminoPositionStorageService = KaminoPositionStorageService(),
        priceService: CryptoPriceServiceProtocol = CryptoPriceService.shared
    ) {
        self.vault = vault
        self.service = service
        self.storage = storage
        self.priceService = priceService
        seedFromPersistedSnapshot()
    }

    /// `true` once the user has enabled at least one vault. The segment shows
    /// the "manage positions" banner until then, matching the stake segment's
    /// opt-in gate.
    var hasEnabledVaults: Bool { !rows.isEmpty }

    /// Rebinds to the vault the screen now shows. The screen outlives a vault
    /// switch (its `StateObject` is built once), so without this a later
    /// refresh would read the new vault's owner address and write the result
    /// into the old vault's rows. Also supersedes any in-flight refresh, whose
    /// results belong to the vault it started on.
    func update(vault: Vault) {
        guard vault.pubKeyECDSA != self.vault.pubKeyECDSA else { return }
        self.vault = vault
        refreshTask?.cancel()
        refreshTask = nil
        seedFromPersistedSnapshot()
    }

    /// Cache-first paint: map the persisted rows into display rows synchronously,
    /// BEFORE any network call, so a warm store renders the last-known position
    /// instantly. Also re-run after the user changes their selection, which is
    /// what makes a newly enabled vault appear with a zero row immediately.
    func seedFromPersistedSnapshot() {
        rows = enabledPositions().map { position, descriptor in
            KaminoEarnRow(
                descriptor: descriptor,
                name: descriptor.fallbackName,
                tokenAmount: position.tokenAmountDecimal,
                apy30d: position.apy30d,
                pnlToken: position.pnlToken
            )
        }
    }

    /// Refreshes every enabled vault and writes the result back to the cache.
    ///
    /// Failure degrades per source, never to a blank segment:
    /// - a failed `/positions` read keeps every seeded row (an RPC/API outage
    ///   must not make a position look like it vanished);
    /// - a failed per-vault state/metrics read keeps that row's cached values,
    ///   because without `tokensPerShare` the shares cannot be valued at all;
    /// - a failed `/pnl` read keeps the last figure that was read, and only
    ///   leaves the profit-and-loss line blank when there has never been one.
    ///
    /// An empty `/positions` response is a real "holds nothing" answer and is
    /// allowed to zero a row — the vault stays listed, since the user enabled it.
    ///
    /// Supersedes any refresh already running, then awaits this one, so a caller
    /// driving a pull-to-refresh still gets a spinner that ends when the work does.
    func refresh(owner: String) async {
        refreshTask?.cancel()
        let task = Task { await performRefresh(owner: owner) }
        refreshTask = task
        await task.value
    }

    private func performRefresh(owner: String) async {
        let enabled = enabledPositions().map(\.descriptor)
        guard !enabled.isEmpty else {
            rows = []
            return
        }

        isLoading = true
        // Only the pass that is still current clears the spinner. A superseded
        // one unwinds after its replacement has already set this, and would
        // otherwise switch it off with a refresh still running.
        defer { if !Task.isCancelled { isLoading = false } }
        error = nil

        await refreshRates(for: enabled)

        let sharesByVault: [String: String]
        do {
            let positions = try await service.fetchPositions(owner: owner)
            sharesByVault = Dictionary(
                positions.map { ($0.vaultAddress, $0.totalShares) },
                uniquingKeysWith: { first, _ in first }
            )
        } catch {
            // A cancelled read is a superseded pass, not a failure the user
            // should see: reporting it would put "cancelled" in the error slot
            // while the refresh that replaced it is still running.
            guard !Task.isCancelled else { return }
            logger.error("Kamino positions read failed: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
            return
        }

        var freshRows: [KaminoEarnRow] = []
        var snapshots: [KaminoPositionSnapshot] = []

        // A row that could not be refreshed keeps its cached figure rather than
        // being dropped or zeroed — the deposit is still there, we just could
        // not read it this time.
        func keepCached(_ descriptor: KaminoVaultDescriptor) {
            if let cached = rows.first(where: { $0.id == descriptor.address }) {
                freshRows.append(cached)
            }
        }

        for descriptor in enabled {
            // Checked per vault rather than only at the end: this loop is one
            // hydration and one PnL read each, and a superseded pass should stop
            // issuing them rather than finish the set and discard the answer.
            guard !Task.isCancelled else { return }

            // The whole descriptor is passed through, never just the address:
            // `fetchVaultInfo` requires the registry's own entry, and the mints,
            // their decimals and the farm are what every later safety check is
            // measured against.
            guard let info = await vaultInfo(for: descriptor) else {
                keepCached(descriptor)
                continue
            }

            // Shares come from the API as a human-units decimal string, parsed
            // exactly at the vault's pinned share scale. A vault ABSENT from the
            // response is a real "holds nothing"; a value that is present but
            // unparseable is a failed read, and must not be rounded down to a
            // zero that would erase a real position from the DeFi total.
            let shares: KaminoShareAmount
            if let reported = sharesByVault[descriptor.address] {
                guard let parsed = KaminoShareAmount(
                    decimalString: reported,
                    decimals: descriptor.sharesDecimals
                ) else {
                    logger.error("Kamino reported unparseable shares for \(descriptor.address, privacy: .public)")
                    keepCached(descriptor)
                    continue
                }
                shares = parsed
            } else {
                shares = KaminoShareAmount(baseUnits: 0, decimals: descriptor.sharesDecimals)
            }

            // `tokensPerShare`, never `sharePrice`: the latter is USD per share
            // and coincides with the token rate only on a dollar vault. On Allez
            // SOL the two differ by ~74×, so using it would overstate the
            // position by the price of SOL.
            guard let tokenAmount = shares.tokenValue(
                tokensPerShare: info.tokensPerShare,
                tokenDecimals: descriptor.tokenDecimals
            ) else {
                logger.error("Kamino share conversion failed for \(descriptor.address, privacy: .public)")
                keepCached(descriptor)
                continue
            }

            // A `/pnl` failure is a "could not confirm", exactly like the reads
            // above, so it keeps what the last successful one established. The
            // figure is persisted as well as displayed: without the fallback a
            // single flaky read would write `nil` over a real value, and the
            // next launch would seed a row whose profit-and-loss line has
            // quietly gone — a display gap outliving the outage that caused it.
            let pnlToken = await pnlToken(owner: owner, descriptor: descriptor)
                ?? cachedPnlToken(for: descriptor)

            freshRows.append(
                KaminoEarnRow(
                    descriptor: descriptor,
                    name: info.name,
                    tokenAmount: tokenAmount.decimalValue,
                    apy30d: info.apy30d,
                    pnlToken: pnlToken
                )
            )
            snapshots.append(
                KaminoPositionSnapshot(
                    vaultAddress: descriptor.address,
                    shares: shares,
                    tokenAmount: tokenAmount,
                    apy30d: info.apy30d,
                    pnlToken: pnlToken
                )
            )
        }

        // A refresh that has been superseded — by a newer one, or by a vault
        // switch — must not publish or persist: its enabled set and its owner
        // address are both stale by now. Persisting is the half that would
        // outlive the session, writing an old vault's figures into the store.
        guard !Task.isCancelled else { return }
        rows = freshRows
        persist(snapshots)
    }

    // MARK: - Private

    /// The enabled rows paired with their registry descriptor, in registry order
    /// so the segment does not reshuffle between refreshes. A row whose vault is
    /// no longer curated is dropped rather than rendered without an identity.
    private func enabledPositions() -> [(position: KaminoPosition, descriptor: KaminoVaultDescriptor)] {
        KaminoVaultRegistry.allowList.compactMap { descriptor in
            guard let position = storage.position(for: vault, vaultAddress: descriptor.address),
                  position.isEnabled
            else { return nil }
            return (position, descriptor)
        }
    }

    /// Loads the rates the Earn cards and the DeFi total are priced with.
    ///
    /// `RateProvider`'s cache is populated from the vault's own coins, and a
    /// deposited token need not be one: a user whose USDC lives inside a vault
    /// and nowhere in their wallet would otherwise have a real position — and
    /// its contribution to the synchronous DeFi total — rendered as zero.
    /// Best-effort: a failure leaves the last-known rate in place.
    private func refreshRates(for descriptors: [KaminoVaultDescriptor]) async {
        // Both dollar vaults share one underlying token — price it once.
        let coins = descriptors.compactMap(\.underlyingCoinMeta).uniqueBy { $0 }
        guard !coins.isEmpty else { return }
        do {
            try await priceService.fetchPrices(coins: coins)
        } catch {
            logger.warning("Kamino rate refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func vaultInfo(for descriptor: KaminoVaultDescriptor) async -> KaminoVaultInfo? {
        do {
            return try await service.fetchVaultInfo(descriptor: descriptor)
        } catch {
            logger.error(
                "Kamino vault \(descriptor.address, privacy: .public) hydration failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// Profit and loss in the underlying token. Quietly `nil` on failure — it is
    /// one display line, and dropping it must never cost the user their position.
    ///
    /// `nil` means "could not read", never "the position has no profit and
    /// loss": a real zero arrives as a parseable `0`. The caller is what turns
    /// that into the cached figure rather than into an erasure.
    private func pnlToken(owner: String, descriptor: KaminoVaultDescriptor) async -> Decimal? {
        do {
            let pnl = try await service.fetchPnl(owner: owner, vault: descriptor.address)
            return KaminoDecimal.parse(pnl.totalPnl.token)
        } catch {
            logger.warning(
                "Kamino PnL read failed for \(descriptor.address, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// The profit and loss a previous pass established for this vault, read from
    /// the rows on display — which are the persisted ones until this refresh
    /// publishes, exactly the source `keepCached` reads.
    private func cachedPnlToken(for descriptor: KaminoVaultDescriptor) -> Decimal? {
        rows.first(where: { $0.id == descriptor.address })?.pnlToken
    }

    private func persist(_ snapshots: [KaminoPositionSnapshot]) {
        guard !snapshots.isEmpty else { return }
        do {
            try storage.upsert(snapshots: snapshots, for: vault)
        } catch {
            logger.error("Failed to persist Kamino snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// One Kamino Earn vault row.
///
/// A display projection: it carries no shares and no rate, so nothing can size a
/// transaction from it.
struct KaminoEarnRow: Identifiable, Equatable {
    var id: String { descriptor.address }

    let descriptor: KaminoVaultDescriptor
    /// On-chain vault name once hydrated, the registry's fallback until then.
    let name: String
    /// Deposited amount in the vault's underlying token, human units.
    let tokenAmount: Decimal
    /// 30-day APY as a fraction (`0.0391` = 3.91%), or `nil` to hide the row.
    let apy30d: Decimal?
    /// Lifetime profit and loss in the underlying token, or `nil` to hide the row.
    let pnlToken: Decimal?

    var curator: String { descriptor.curator }
    var riskTier: KaminoRiskTier { descriptor.riskTier }
    /// The wallet coin the amount is denominated in — its ticker, logo and rate.
    var coin: CoinMeta? { descriptor.underlyingCoinMeta }
}
