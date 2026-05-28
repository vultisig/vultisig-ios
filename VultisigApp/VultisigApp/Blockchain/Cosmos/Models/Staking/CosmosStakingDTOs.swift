//
//  CosmosStakingDTOs.swift
//  VultisigApp
//
//  Read-side DTOs for Cosmos-SDK x/staking + x/distribution LCD endpoints.
//  Shape mirrors the SDK's `lcdQueries.ts` types in
//  `vultisig-sdk/packages/core/chain/chains/cosmos/staking/lcdQueries.ts` —
//  same field names (snake_case on the wire, mapped to camelCase here via
//  `CodingKeys`), same optionality, same fallback behaviour for fresh
//  delegators that don't yet have a rewards entry.
//

import Foundation

// MARK: - Wire-level coin

struct CosmosStakingCoin: Codable, Equatable {
    let denom: String
    let amount: String
}

// MARK: - Delegations

struct CosmosDelegation: Equatable {
    let validatorAddress: String
    let balance: CosmosStakingCoin
    /// `shares` is a `cosmos.Dec` (18-decimal fixed-point) string on the
    /// wire. We expose it as the raw string — UI consumers convert via
    /// `Decimal(string:)` when needed.
    let shares: String
}

struct CosmosDelegationResponse: Decodable {
    let delegationResponses: [DelegationResponseEntry]

    enum CodingKeys: String, CodingKey {
        case delegationResponses = "delegation_responses"
    }

    struct DelegationResponseEntry: Decodable {
        let delegation: DelegationInner
        let balance: CosmosStakingCoin

        struct DelegationInner: Decodable {
            let delegatorAddress: String
            let validatorAddress: String
            let shares: String

            enum CodingKeys: String, CodingKey {
                case delegatorAddress = "delegator_address"
                case validatorAddress = "validator_address"
                case shares
            }
        }
    }

    func toDelegations() -> [CosmosDelegation] {
        delegationResponses.map { entry in
            CosmosDelegation(
                validatorAddress: entry.delegation.validatorAddress,
                balance: entry.balance,
                shares: entry.delegation.shares
            )
        }
    }
}

// MARK: - Unbonding delegations

struct CosmosUnbondingDelegation: Equatable {
    let validatorAddress: String
    let entries: [CosmosUnbondingEntry]
}

struct CosmosUnbondingEntry: Equatable, Codable {
    let creationHeight: Int64
    let completionTime: Date
    let initialBalance: Decimal
    let balance: Decimal
}

struct CosmosUnbondingDelegationResponse: Decodable {
    let unbondingResponses: [UnbondingDelegationEntry]

    enum CodingKeys: String, CodingKey {
        case unbondingResponses = "unbonding_responses"
    }

    struct UnbondingDelegationEntry: Decodable {
        let validatorAddress: String
        let entries: [WireEntry]

        enum CodingKeys: String, CodingKey {
            case validatorAddress = "validator_address"
            case entries
        }

        struct WireEntry: Decodable {
            let creationHeight: String
            let completionTime: String
            let initialBalance: String
            let balance: String

            enum CodingKeys: String, CodingKey {
                case creationHeight = "creation_height"
                case completionTime = "completion_time"
                case initialBalance = "initial_balance"
                case balance
            }
        }
    }

    func toUnbondingDelegations() -> [CosmosUnbondingDelegation] {
        unbondingResponses.map { wire in
            CosmosUnbondingDelegation(
                validatorAddress: wire.validatorAddress,
                entries: wire.entries.compactMap(Self.makeEntry)
            )
        }
    }

    private static func makeEntry(_ wire: UnbondingDelegationEntry.WireEntry) -> CosmosUnbondingEntry? {
        guard let creationHeight = Int64(wire.creationHeight),
              let completion = CosmosStakingDateParser.parse(wire.completionTime),
              let initialBalance = Decimal(string: wire.initialBalance),
              let balance = Decimal(string: wire.balance) else {
            return nil
        }
        return CosmosUnbondingEntry(
            creationHeight: creationHeight,
            completionTime: completion,
            initialBalance: initialBalance,
            balance: balance
        )
    }
}

// MARK: - Rewards

struct CosmosDelegatorReward: Equatable {
    let validatorAddress: String
    /// Multi-asset rewards are technically possible (e.g. a chain that
    /// rewards in multiple denoms). v1 aggregates by denom downstream and
    /// surfaces only the bond denom total; the full array is preserved
    /// here so v1.1 can expand the per-validator row without a DTO change.
    let reward: [CosmosStakingCoin]
}

struct CosmosDelegatorRewards: Equatable {
    let rewards: [CosmosDelegatorReward]
    let total: [CosmosStakingCoin]
}

struct CosmosDelegatorRewardsResponse: Decodable {
    /// Both `rewards` and `total` arrive as `null` on some LCD firmwares
    /// when the delegator has never accrued any rewards. The SDK falls
    /// back to `[]` at `lcdQueries.ts:198-202`; iOS does the same.
    let rewards: [WireReward]?
    let total: [WireCoin]?

    struct WireReward: Decodable {
        let validatorAddress: String
        let reward: [WireCoin]?

        enum CodingKeys: String, CodingKey {
            case validatorAddress = "validator_address"
            case reward
        }
    }

    struct WireCoin: Decodable {
        let denom: String
        /// LCD returns reward amounts as `cosmos.Dec` strings — they
        /// frequently include a fractional component because rewards
        /// accrue per-block. We keep them as the raw string at the DTO
        /// boundary and let the position-aggregation layer convert.
        let amount: String
    }

    func toRewards() -> CosmosDelegatorRewards {
        let rewards = (self.rewards ?? []).map { wire in
            CosmosDelegatorReward(
                validatorAddress: wire.validatorAddress,
                reward: (wire.reward ?? []).map { CosmosStakingCoin(denom: $0.denom, amount: $0.amount) }
            )
        }
        let total = (self.total ?? []).map { CosmosStakingCoin(denom: $0.denom, amount: $0.amount) }
        return CosmosDelegatorRewards(rewards: rewards, total: total)
    }
}

// MARK: - Validators

struct CosmosValidator: Equatable {
    let operatorAddress: String
    let moniker: String
    /// Commission rate as a fixed-point `cosmos.Dec` (1.0 = 100%). Display
    /// layer multiplies by 100 to render "5%". Keep as `Decimal` to avoid
    /// floating-point drift in sort comparisons.
    let commission: Decimal
    let jailed: Bool
    let status: Status
    /// Voting power proxied via `tokens` (uint string of bond-denom base
    /// units). Sufficient for sort-by-power without pulling
    /// staking-pool totals. Future "% of pool" UX needs the pool fetch.
    let votingPower: Decimal
    /// Keybase identity advertised in the validator description. When set,
    /// resolves to a profile-picture URL via the Keybase user lookup; absent
    /// or unresolved validators fall back to the deterministic monogram
    /// avatar.
    let identity: String?

    init(
        operatorAddress: String,
        moniker: String,
        commission: Decimal,
        jailed: Bool,
        status: Status,
        votingPower: Decimal,
        identity: String? = nil
    ) {
        self.operatorAddress = operatorAddress
        self.moniker = moniker
        self.commission = commission
        self.jailed = jailed
        self.status = status
        self.votingPower = votingPower
        self.identity = identity
    }

    enum Status: String, Equatable, Codable {
        case bonded
        case unbonded
        case unbonding
        case unspecified
    }
}

struct CosmosValidatorListResponse: Decodable {
    let validators: [WireValidator]

    struct WireValidator: Decodable {
        let operatorAddress: String
        let jailed: Bool?
        let status: String
        let tokens: String
        let description: WireDescription
        let commission: WireCommission

        enum CodingKeys: String, CodingKey {
            case operatorAddress = "operator_address"
            case jailed
            case status
            case tokens
            case description
            case commission
        }

        struct WireDescription: Decodable {
            let moniker: String
            /// Optional Keybase identity (16-hex string by convention). The
            /// SDK / Windows resolve this through `keybase.io/_/api/1.0/user/
            /// lookup.json?key_suffix=…&fields=pictures`. Many validators
            /// omit it — keep the field optional so a missing `identity`
            /// doesn't fail the entire validator-list decode.
            let identity: String?
        }

        struct WireCommission: Decodable {
            let commissionRates: WireRates

            enum CodingKeys: String, CodingKey {
                case commissionRates = "commission_rates"
            }

            struct WireRates: Decodable {
                let rate: String
            }
        }
    }

    func toValidators() -> [CosmosValidator] {
        validators.map { wire in
            let identity = wire.description.identity
                .flatMap { $0.isEmpty ? nil : $0 }
            return CosmosValidator(
                operatorAddress: wire.operatorAddress,
                moniker: wire.description.moniker,
                commission: Decimal(string: wire.commission.commissionRates.rate) ?? 0,
                jailed: wire.jailed ?? false,
                status: mapStatus(wire.status),
                votingPower: Decimal(string: wire.tokens) ?? 0,
                identity: identity
            )
        }
    }

    private func mapStatus(_ raw: String) -> CosmosValidator.Status {
        switch raw {
        case "BOND_STATUS_BONDED": return .bonded
        case "BOND_STATUS_UNBONDED": return .unbonded
        case "BOND_STATUS_UNBONDING": return .unbonding
        default: return .unspecified
        }
    }
}

// MARK: - Redelegations (used by the cooldown gate)

struct CosmosRedelegationEntry: Equatable {
    let srcValidator: String
    let dstValidator: String
    let completionTime: Date
}

struct CosmosRedelegationResponse: Decodable {
    let redelegationResponses: [Entry]

    enum CodingKeys: String, CodingKey {
        case redelegationResponses = "redelegation_responses"
    }

    struct Entry: Decodable {
        let redelegation: Redelegation
        let entries: [WireEntry]

        struct Redelegation: Decodable {
            let validatorSrcAddress: String
            let validatorDstAddress: String

            enum CodingKeys: String, CodingKey {
                case validatorSrcAddress = "validator_src_address"
                case validatorDstAddress = "validator_dst_address"
            }
        }

        struct WireEntry: Decodable {
            let redelegationEntry: RedelegationEntry

            enum CodingKeys: String, CodingKey {
                case redelegationEntry = "redelegation_entry"
            }

            struct RedelegationEntry: Decodable {
                let completionTime: String

                enum CodingKeys: String, CodingKey {
                    case completionTime = "completion_time"
                }
            }
        }
    }

    func toRedelegations() -> [CosmosRedelegationEntry] {
        var out: [CosmosRedelegationEntry] = []
        for entry in redelegationResponses {
            for wire in entry.entries {
                guard let date = CosmosStakingDateParser.parse(wire.redelegationEntry.completionTime) else {
                    continue
                }
                out.append(
                    CosmosRedelegationEntry(
                        srcValidator: entry.redelegation.validatorSrcAddress,
                        dstValidator: entry.redelegation.validatorDstAddress,
                        completionTime: date
                    )
                )
            }
        }
        return out
    }
}

// MARK: - Shared date parser

/// LCD wire dates arrive in two shapes — RFC3339 with fractional seconds
/// (`2026-06-02T13:00:00.123456789Z`, from per-block payouts that don't
/// align to whole seconds) and without (`2026-06-10T10:00:00Z`, from
/// gov-proposal or genesis-anchored entries). One `ISO8601DateFormatter`
/// only accepts one of those — we try the fractional form first because
/// it's the more common shape, then fall back to the plain form.
enum CosmosStakingDateParser {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let withoutFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: String) -> Date? {
        if let date = withFraction.date(from: value) {
            return date
        }
        return withoutFraction.date(from: value)
    }
}
