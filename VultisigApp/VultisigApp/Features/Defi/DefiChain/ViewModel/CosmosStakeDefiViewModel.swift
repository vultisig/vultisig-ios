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

    /// Fan-outs the four LCD reads (delegations, unbonding, rewards,
    /// bonded validators) and folds them into per-validator rows keyed by
    /// valoper address. Per-call failures degrade individually — a failed
    /// rewards fetch renders the position with zero pending rewards rather
    /// than dropping the row, matching THOR/Maya behavior under transient
    /// LCD outages. The validators query enriches each row with the
    /// moniker, commission-adjusted APY, and bonded-status badge — when
    /// the validator query fails, rows fall back to the truncated valoper
    /// and "—" APY but the staked amount + actions stay usable.
    func refresh(address: String, decimals: Int) async {
        isLoading = true
        defer { isLoading = false }
        error = nil

        async let delegationsTask = fetchDelegations(address: address)
        async let unbondingsTask = fetchUnbondings(address: address)
        async let rewardsTask = fetchRewards(address: address)
        async let validatorsTask = fetchValidators()

        let delegations = await delegationsTask
        let unbondings = await unbondingsTask
        let rewards = await rewardsTask
        let validators = await validatorsTask

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

        let validatorsByAddress = Dictionary(
            uniqueKeysWithValues: validators.map { ($0.operatorAddress, $0) }
        )

        let divisor = pow(Decimal(10), decimals)
        let baselineAPY = Self.baselineAPY(for: chain)

        positions = delegations.map { delegation in
            let raw = Decimal(string: delegation.balance.amount) ?? 0
            let pendingRaw = rewardsByValidator[delegation.validatorAddress] ?? 0
            let validator = validatorsByAddress[delegation.validatorAddress]

            // /cosmos/staking/v1beta1/validators?status=BOND_STATUS_BONDED
            // only returns active set members. A delegated validator
            // missing from the response is either jailed or unbonded —
            // either way, "Churned Out" is the right user-facing label
            // and Unstake is the only sensible action.
            let status: CosmosStakePositionRow.ValidatorStatus
            switch validator {
            case .some(let value) where !value.jailed && value.status == .bonded:
                status = .active
            case .some:
                status = .churnedOut
            case .none:
                status = .churnedOut
            }

            let apy: Decimal?
            if let baseline = baselineAPY, let validator {
                apy = baseline * (1 - validator.commission)
            } else {
                apy = nil
            }

            return CosmosStakePositionRow(
                validatorAddress: delegation.validatorAddress,
                validatorMoniker: validator?.moniker ?? "",
                stakedAmount: raw / divisor,
                pendingReward: pendingRaw / divisor,
                apyPercent: apy,
                validatorStatus: status
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

    private func fetchValidators() async -> [CosmosValidator] {
        do {
            return try await stakingService.fetchValidators(chain: chain)
        } catch {
            logger.warning("Failed to fetch validators: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Per-chain APY baseline used to derive the per-validator APY display.
    /// We multiply by `(1 - commission)` at the row level. The baselines
    /// here are directional, not chain-precise — a full computation would
    /// pull `/cosmos/mint/v1beta1/inflation`,
    /// `/cosmos/distribution/v1beta1/params` (community tax), and the
    /// bonded-ratio from the staking pool, then apply
    /// `inflation × (1 - tax) / bondedRatio × (1 - commission)`. v1 trades
    /// that LCD fan-out for a single multiplier so the populated card
    /// renders without an extra refresh dependency.
    /// - LUNA (phoenix-1): ~12.5% pre-commission, well within the
    ///   historical 9-13% range.
    /// - LUNC (columbus-5): no stable on-chain baseline since the chain
    ///   split — return `nil` and the UI surfaces an em-dash.
    private static func baselineAPY(for chain: Chain) -> Decimal? {
        switch chain {
        case .terra:
            return Decimal(string: "0.125")
        default:
            return nil
        }
    }
}

/// Per-validator row in the DeFi stake segment. `validatorMoniker`,
/// `apyPercent`, and `validatorStatus` are derived from the bonded
/// validator list — when that LCD call fails, the row falls back to
/// the truncated valoper, a nil APY, and `.churnedOut` (the
/// conservative default so Unstake stays the obvious action).
struct CosmosStakePositionRow: Identifiable, Equatable, Sendable {
    var id: String { validatorAddress }
    let validatorAddress: String
    let validatorMoniker: String
    let stakedAmount: Decimal
    let pendingReward: Decimal
    /// Fractional APY (`0.05` = 5%). `nil` when the validator metadata
    /// couldn't be enriched or the chain has no baseline (e.g. LUNC).
    let apyPercent: Decimal?
    let validatorStatus: ValidatorStatus

    enum ValidatorStatus: Equatable, Sendable {
        case active
        case churnedOut
    }
}
