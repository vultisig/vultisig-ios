//
//  RewardsPayoutViewModel.swift
//  VultisigApp
//

import Foundation

/// State for the Rewards Payout sheet of one bonded THORChain node: the vault's
/// current Bond Yield share, read live, and the share being chosen.
@MainActor
final class RewardsPayoutViewModel: ObservableObject, Identifiable, Equatable {
    nonisolated static func == (lhs: RewardsPayoutViewModel, rhs: RewardsPayoutViewModel) -> Bool {
        lhs.id == rhs.id
    }

    let id = UUID()
    let vault: Vault
    let coin: Coin
    let nodeAddress: String
    let bondedAmount: Decimal
    let nextReward: Decimal

    @Published var percentage: Double? = 0
    /// The share the sheet opened with, in whole percent; nil until read.
    @Published private(set) var initialPercentage: Int?
    @Published private(set) var loadFailed = false
    @Published private(set) var isPreparing = false

    private let thorchainAPIService = THORChainAPIService()
    private var loadTask: Task<Void, Never>?

    init(vault: Vault, coin: Coin, position: BondPosition) {
        self.vault = vault
        self.coin = coin
        self.nodeAddress = position.node.address
        self.bondedAmount = position.amount
        self.nextReward = position.nextReward
    }

    var selectedPercentage: Int { Int(percentage ?? 0) }

    var canContinue: Bool {
        guard let initialPercentage, !isPreparing else { return false }
        return selectedPercentage != initialPercentage
    }

    func load() {
        loadTask?.cancel()
        loadFailed = false
        loadTask = Task {
            do {
                let details = try await thorchainAPIService.getNodeDetails(nodeAddress: nodeAddress)
                try Task.checkCancellation()
                guard let bps = details.payoutBps(for: coin.address) else {
                    loadFailed = true
                    return
                }
                let loaded = bps / BondYieldTransactionBuilder.basisPointsPerPercent
                initialPercentage = loaded
                percentage = Double(loaded)
            } catch is CancellationError {
                return
            } catch {
                loadFailed = true
            }
        }
    }

    func cancelLoad() {
        loadTask?.cancel()
    }

    /// The priced review for the chosen share, or nil when it cannot be built.
    func prepareReview() async -> KeysignReview? {
        guard canContinue,
              let builder = BondYieldTransactionBuilder(
                coin: coin,
                nodeAddress: nodeAddress,
                payoutPercentage: selectedPercentage
              ) else { return nil }
        isPreparing = true
        defer { isPreparing = false }
        let tx = await builder.buildPricedSendTransaction(vault: vault)
        return .functionTransaction(tx: tx, vault: vault)
    }
}
