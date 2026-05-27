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
    private let apyResolver: CosmosStakingAPYResolverProtocol
    private let logger = Logger(
        subsystem: "com.vultisig.app",
        category: "cosmos-stake-defi-vm"
    )

    init(
        chain: Chain,
        stakingService: CosmosStakingServiceProtocol = CosmosStakingService(),
        apyResolver: CosmosStakingAPYResolverProtocol = CosmosStakingAPYResolver()
    ) {
        self.chain = chain
        self.stakingService = stakingService
        self.apyResolver = apyResolver
    }

    /// Fan-outs the four LCD reads (delegations, unbonding, rewards,
    /// bonded validators) plus the chain-wide APY inputs, then folds them
    /// into per-validator rows keyed by valoper address. Per-call failures
    /// degrade individually — a failed rewards fetch renders the position
    /// with zero pending rewards rather than dropping the row, matching
    /// THOR/Maya behavior under transient LCD outages. The validators
    /// query enriches each row with the moniker, commission-adjusted APY,
    /// Keybase identity, and bonded-status badge; the per-validator APY is
    /// computed from `(1 - communityTax) × (inflation / bondedRatio) ×
    /// (1 - commission)` with a baseline-times-(1 - commission) fallback
    /// when any of the 4 APY LCD calls fails. Pending unbondings are
    /// grouped per validator so rows can lock both Undelegate and
    /// Redelegate while an entry is mid-unbond.
    func refresh(address: String, decimals: Int) async {
        isLoading = true
        defer { isLoading = false }
        error = nil

        async let delegationsTask = fetchDelegations(address: address)
        async let unbondingsTask = fetchUnbondings(address: address)
        async let rewardsTask = fetchRewards(address: address)
        async let validatorsTask = fetchValidators()
        async let chainApyTask = fetchChainApy()

        let delegations = await delegationsTask
        let unbondings = await unbondingsTask
        let rewards = await rewardsTask
        let validators = await validatorsTask
        let chainApy = await chainApyTask

        // Filter rewards to the chain's bond denom before summing — Terra
        // Classic LCDs occasionally return reward entries in non-staking
        // denoms (legacy stability-tax pool), and aggregating them as if
        // they were `uluna` overstates the user's claimable native
        // rewards. Mirrors `CosmosDelegationsView.tsx` reward filtering on
        // Windows.
        let bondDenom = (try? CosmosStakingConfig.bondDenom(for: chain)) ?? ""
        let rewardsByValidator = Dictionary(
            grouping: rewards.rewards,
            by: \.validatorAddress
        ).mapValues { entries in
            entries
                .flatMap(\.reward)
                .filter { $0.denom == bondDenom }
                .reduce(into: Decimal(0)) { acc, coin in
                    acc += (Decimal(string: coin.amount) ?? 0)
                }
        }

        let validatorsByAddress = Dictionary(
            uniqueKeysWithValues: validators.map { ($0.operatorAddress, $0) }
        )

        let unbondingsByValidator = Dictionary(
            grouping: unbondings,
            by: \.validatorAddress
        )

        let divisor = pow(Decimal(10), decimals)
        let now = Date()

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

            let apy = Self.computeAPY(
                chainApy: chainApy,
                resolver: self.apyResolver,
                chain: self.chain,
                validator: validator
            )

            let pendingUnlock = unbondingsByValidator[delegation.validatorAddress]?
                .flatMap(\.entries)
                .filter { $0.completionTime > now }
                .min(by: { $0.completionTime < $1.completionTime })?
                .completionTime

            return CosmosStakePositionRow(
                validatorAddress: delegation.validatorAddress,
                validatorMoniker: validator?.moniker ?? "",
                validatorIdentity: validator?.identity,
                stakedAmount: raw / divisor,
                pendingReward: pendingRaw / divisor,
                apyPercent: apy,
                validatorStatus: status,
                pendingUnbondingUnlockDate: pendingUnlock
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

    /// Resolves the chain-level APY inputs once per refresh. Returns `nil`
    /// when the bond denom is unavailable (chain unsupported) or every LCD
    /// fan-out attempt fails inside the resolver — both cases drop the
    /// caller to the per-chain baseline fallback.
    private func fetchChainApy() async -> CosmosChainApyData? {
        guard let denom = try? CosmosStakingConfig.bondDenom(for: chain) else {
            return nil
        }
        return await apyResolver.chainApy(chain: chain, stakingDenom: denom)
    }

    /// Combines the resolver output + per-validator commission into the
    /// displayed APY. When the LCD fan-out failed, falls back to the
    /// per-chain baseline (12.5% for LUNA, nil for LUNC) — the UI hides
    /// the row when the resulting value is nil.
    private static func computeAPY(
        chainApy: CosmosChainApyData?,
        resolver: CosmosStakingAPYResolverProtocol,
        chain: Chain,
        validator: CosmosValidator?
    ) -> Decimal? {
        let commission = validator?.commission ?? 0
        if let chainApy {
            return CosmosStakingAPYResolver.computeValidatorAPY(
                chainData: chainApy,
                commission: commission
            )
        }
        guard let baseline = resolver.baselineFallback(chain: chain), validator != nil else {
            return nil
        }
        let apy = baseline * (1 - commission)
        return apy > 0 ? apy : nil
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
    /// Keybase identity advertised by the validator — used to swap in the
    /// remote avatar in `validatorAvatar(for:)`. Nil when the validator
    /// omits the field or when the validators query fell back to the
    /// "Churned Out" default.
    let validatorIdentity: String?
    let stakedAmount: Decimal
    let pendingReward: Decimal
    /// Fractional APY (`0.05` = 5%). `nil` when the validator metadata
    /// couldn't be enriched, when the chain APY fan-out failed and no
    /// baseline exists (e.g. LUNC), or when inflation × bonded ratio
    /// collapses to zero. The view layer hides the APY row entirely when
    /// this is nil — matching the populated-card Figma.
    let apyPercent: Decimal?
    let validatorStatus: ValidatorStatus
    /// Earliest non-expired unbonding completion timestamp for the
    /// validator, or `nil` when there are no pending unbondings. When
    /// non-nil, the row disables Undelegate + Redelegate and renders an
    /// "Unlocks {date}" footer beneath the action buttons.
    let pendingUnbondingUnlockDate: Date?

    enum ValidatorStatus: Equatable, Sendable {
        case active
        case churnedOut
    }
}
