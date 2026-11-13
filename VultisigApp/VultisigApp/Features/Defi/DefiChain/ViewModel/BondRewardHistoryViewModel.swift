//
//  BondRewardHistoryViewModel.swift
//  VultisigApp
//
//  Drives the "Total Rewards Earned" sheet for a bonded node or the TCY
//  stake. History is lazy — fetched only once the sheet actually opens — and
//  cancellable, since closing the sheet mid-fetch should not keep requests
//  running for a view nobody is looking at.
//

import Foundation
import OSLog

private let logger = Log.defi.viewModel

@MainActor
final class BondRewardHistoryViewModel: ObservableObject {
    @Published private(set) var history: [BondRewardHistoryEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?
    /// `false` when some rewards could not be loaded, so `total` may be short.
    @Published private(set) var isHistoryComplete = true

    let coin: Coin
    /// Names whose rewards these are, under the header total.
    let subtitle: String
    /// Live share still accruing toward the next payout — the sheet's
    /// Upcoming row, in base units of `coin`; nil leaves the row out. Comes
    /// off the already-loaded position, so it never waits on the history fetch.
    let upcomingAmount: Decimal?

    private let fetchHistory: @MainActor () async throws -> BondRewardHistory
    private var fetchTask: Task<Void, Never>?

    /// Sum of realized (dated) rows only — Upcoming is excluded per the
    /// issue's "Total = sum of dated rows" acceptance criterion.
    var total: Decimal {
        history.reduce(Decimal.zero) { $0 + $1.amount }
    }

    init(
        coin: Coin,
        subtitle: String,
        upcomingAmount: Decimal?,
        fetchHistory: @escaping @MainActor () async throws -> BondRewardHistory
    ) {
        self.coin = coin
        self.subtitle = subtitle
        self.upcomingAmount = upcomingAmount
        self.fetchHistory = fetchHistory
    }

    /// A bonded node's last churns, opened from the node card's Last Reward cell.
    convenience init(vault: Vault, chain: Chain, coin: Coin, node: BondPosition, interactor: BondInteractor? = nil) {
        let interactor = interactor ?? DefiInteractorResolver.bondInteractor(for: chain)
        self.init(
            coin: coin,
            subtitle: String(format: "rewardHistoryNodeAddress".localized, node.node.address.truncatedAddress),
            upcomingAmount: node.nextReward
        ) {
            guard let interactor, let myBondAddress = await interactor.bondCoinAddress(in: vault) else {
                throw RewardHistoryUnavailableError()
            }
            return try await interactor.fetchRewardHistory(nodeAddress: node.node.address, myBondAddress: myBondAddress)
        }
    }

    /// `estimatedReward` is in whole RUNE, as the card shows it.
    convenience init(tcyStakerAddress address: String, runeCoin: Coin, estimatedReward: Decimal?) {
        self.init(
            coin: runeCoin,
            subtitle: String(format: "stakedCoin".localized, TokensStore.tcy.ticker),
            upcomingAmount: estimatedReward.map { runeCoin.decimalToCrypto(value: $0) }
        ) {
            BondRewardHistory(
                entries: try await THORChainStakingService.shared.fetchTcyRewardHistory(address: address),
                isComplete: true
            )
        }
    }

    /// Starts the fetch only if nothing has been loaded (or failed) yet —
    /// safe to call from `.onAppear`, which can fire more than once.
    func loadIfNeeded() {
        guard fetchTask == nil, history.isEmpty, loadError == nil else { return }
        load()
    }

    func load() {
        fetchTask?.cancel()
        isLoading = true
        loadError = nil
        fetchTask = Task { [weak self] in
            await self?.performLoad()
        }
    }

    /// Called when the sheet is dismissed — releases the in-flight requests
    /// rather than letting them run to completion for a view that is gone.
    func cancelLoad() {
        fetchTask?.cancel()
        fetchTask = nil
    }

    private func performLoad() async {
        // Guarded rather than unconditional: if `load()` is called again
        // before this task finishes, `fetchTask?.cancel()` cancels THIS
        // task, and `Task.isCancelled` reads true for it specifically —
        // so a stale, cancelled task's cleanup never clobbers `isLoading`
        // out from under the replacement task that superseded it.
        defer {
            if !Task.isCancelled {
                isLoading = false
            }
        }

        do {
            let result = try await fetchHistory()
            guard !Task.isCancelled else { return }
            history = result.entries
            isHistoryComplete = result.isComplete
        } catch {
            guard !Task.isCancelled else { return }
            // History-only failure: the list this sheet was opened from is
            // untouched, only this sheet shows the error state.
            logger.error("Failed to load reward history (\(self.subtitle)): \(error)")
            loadError = "rewardHistoryUnavailable".localized
        }
    }
}

/// No interactor for the chain, or no bond address in the vault.
private struct RewardHistoryUnavailableError: Error {}

// Lets the sheet be presented with `crossPlatformSheet(item:)`, so its content
// receives the view model instead of reading optional state mid-presentation.
extension BondRewardHistoryViewModel: Identifiable, Equatable {
    nonisolated static func == (lhs: BondRewardHistoryViewModel, rhs: BondRewardHistoryViewModel) -> Bool {
        lhs === rhs
    }
}
