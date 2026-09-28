//
//  BondRewardHistoryViewModel.swift
//  VultisigApp
//
//  Drives the "Total Rewards Earned" sheet. History is lazy — fetched only
//  once the sheet actually opens — and cancellable, since closing the sheet
//  mid-fetch should not keep up to 20 historical requests running for a view
//  nobody is looking at.
//

import Foundation
import OSLog

private let logger = Log.defi.viewModel

@MainActor
final class BondRewardHistoryViewModel: ObservableObject {
    @Published private(set) var history: [BondRewardHistoryEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    let coin: Coin
    let node: BondPosition

    private let vault: Vault
    private let interactor: BondInteractor?
    private var fetchTask: Task<Void, Never>?

    /// Live share still accruing toward the next churn — the sheet's
    /// Upcoming row. Comes straight off the already-loaded `BondPosition`,
    /// so it never waits on `fetchRewardHistory`.
    var upcomingAmount: Decimal { node.nextReward }

    /// Sum of realized (dated) rows only — Upcoming is excluded per the
    /// issue's "Total = sum of dated rows" acceptance criterion.
    var total: Decimal {
        history.reduce(Decimal.zero) { $0 + $1.amount }
    }

    init(vault: Vault, chain: Chain, coin: Coin, node: BondPosition, interactor: BondInteractor? = nil) {
        self.vault = vault
        self.coin = coin
        self.node = node
        self.interactor = interactor ?? DefiInteractorResolver.bondInteractor(for: chain)
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

    /// Called when the sheet is dismissed — releases the up-to-20 in-flight
    /// historical requests rather than letting them run to completion for a
    /// view that is gone.
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

        guard let interactor else {
            loadError = "rewardHistoryUnavailable".localized
            return
        }
        guard let myBondAddress = await interactor.bondCoinAddress(in: vault) else {
            loadError = "rewardHistoryUnavailable".localized
            return
        }

        do {
            let entries = try await interactor.fetchRewardHistory(
                nodeAddress: node.node.address,
                myBondAddress: myBondAddress
            )
            guard !Task.isCancelled else { return }
            history = entries
        } catch {
            guard !Task.isCancelled else { return }
            // History-only failure: the bonded list this sheet was opened
            // from is untouched, only this sheet shows the error state.
            logger.error("Failed to load reward history for node \(self.node.node.address): \(error)")
            loadError = "rewardHistoryUnavailable".localized
        }
    }
}
