//
//  CosmosStakeDefiViewModel.swift
//  VultisigApp
//
//  Backs the LUNA / LUNC stake segment on the DeFi tab. Aggregates
//  delegations + pending rewards + unbonding entries from the LCD into a
//  per-validator view model, surfaced to the UI as `CosmosStakePositionRow`
//  rows. Refresh is fired on `.onLoad` and on pull-to-refresh.
//
//  This is the data-layer counterpart to the position-card UI in
//  `CosmosStakeDefiView` — the full Figma-aligned populated/empty layout
//  lives there.
//

import Foundation
import Combine
import OSLog

@MainActor
final class CosmosStakeDefiViewModel: ObservableObject {
    let chain: Chain
    @Published private(set) var positions: [CosmosStakePositionRow] = []
    @Published private(set) var pendingUnbondings: [CosmosUnbondingDelegation] = []
    @Published private(set) var totalStaked: Decimal = 0
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?

    private let stakingService: CosmosStakingServiceProtocol
    private let logger = Logger(
        subsystem: "com.vultisig.app",
        category: "cosmos-stake-defi-vm"
    )

    init(
        chain: Chain,
        stakingService: CosmosStakingServiceProtocol = CosmosStakingService()
    ) {
        self.chain = chain
        self.stakingService = stakingService
    }

    /// Fan-outs the three LCD reads (delegations, unbonding, rewards) and
    /// folds them into per-validator rows keyed by valoper address.
    /// Per-call failures degrade individually — a failed rewards fetch
    /// renders the position with zero pending rewards rather than dropping
    /// the row, matching THOR/Maya behavior under transient LCD outages.
    func refresh(address: String, decimals: Int) async {
        isLoading = true
        defer { isLoading = false }
        error = nil

        async let delegationsTask = fetchDelegations(address: address)
        async let unbondingsTask = fetchUnbondings(address: address)
        async let rewardsTask = fetchRewards(address: address)

        let delegations = await delegationsTask
        let unbondings = await unbondingsTask
        let rewards = await rewardsTask

        let rewardsByValidator = Dictionary(
            grouping: rewards.rewards,
            by: \.validatorAddress
        ).mapValues { entries in
            entries
                .flatMap(\.reward)
                .reduce(into: Decimal(0)) { acc, coin in
                    acc += (Decimal(string: coin.amount) ?? 0)
                }
        }

        let divisor = pow(Decimal(10), decimals)

        positions = delegations.map { delegation in
            let raw = Decimal(string: delegation.balance.amount) ?? 0
            let pendingRaw = rewardsByValidator[delegation.validatorAddress] ?? 0
            return CosmosStakePositionRow(
                validatorAddress: delegation.validatorAddress,
                validatorMoniker: "",
                stakedAmount: raw / divisor,
                pendingReward: pendingRaw / divisor
            )
        }

        totalStaked = positions.map(\.stakedAmount).reduce(0, +)
        pendingUnbondings = unbondings

        if positions.isEmpty {
            logger.info("No active delegations for \(self.chain.rawValue, privacy: .public) at \(address, privacy: .private)")
        }
    }

    private func fetchDelegations(address: String) async -> [CosmosDelegation] {
        do {
            return try await stakingService.fetchDelegations(chain: chain, address: address)
        } catch {
            logger.error("Failed to fetch delegations: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
            return []
        }
    }

    private func fetchUnbondings(address: String) async -> [CosmosUnbondingDelegation] {
        do {
            return try await stakingService.fetchUnbondingDelegations(chain: chain, address: address)
        } catch {
            logger.warning("Failed to fetch unbondings: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func fetchRewards(address: String) async -> CosmosDelegatorRewards {
        do {
            return try await stakingService.fetchDelegatorRewards(chain: chain, address: address)
        } catch {
            logger.warning("Failed to fetch rewards: \(error.localizedDescription, privacy: .public)")
            return CosmosDelegatorRewards(rewards: [], total: [])
        }
    }
}

/// Per-validator row in the DeFi stake segment. `validatorMoniker` is
/// optional today (LCD fetches validator metadata in a separate call
/// the v1 view-model doesn't trigger to keep the network footprint
/// small; the position row shows the truncated valoper as a fallback).
struct CosmosStakePositionRow: Identifiable, Equatable, Sendable {
    var id: String { validatorAddress }
    let validatorAddress: String
    let validatorMoniker: String
    let stakedAmount: Decimal
    let pendingReward: Decimal
}
