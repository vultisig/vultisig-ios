//
//  CosmosStakingAPI.swift
//  VultisigApp
//
//  Read-side TargetType for Cosmos-SDK x/staking + x/distribution LCD
//  endpoints. The path layout mirrors the SDK consumer at
//  `vultisig-sdk/packages/core/chain/chains/cosmos/staking/lcdQueries.ts`.
//
//  Base URL is supplied by the caller via `CosmosServiceConfig.baseURL`
//  (already wired for Terra phoenix-1 and TerraClassic columbus-5). Keeping
//  the chain off this struct lets the same TargetType serve both chains —
//  only the host differs.
//

import Foundation

struct CosmosStakingAPI: TargetType {
    let baseURL: URL
    let endpoint: Endpoint

    enum Endpoint {
        case delegations(address: String)
        case unbondingDelegations(address: String)
        case delegatorRewards(address: String)
        /// Validator list. We hardcode `status=BOND_STATUS_BONDED` and
        /// `pagination.limit=300` — the agent app uses the same caps. Terra
        /// has roughly 130 active validators today; 300 keeps headroom
        /// without paging. If a chain ever exceeds 300, the resolver layer
        /// will need to page — surfaced via a follow-up.
        case bondedValidators
        case redelegations(address: String)
        /// `/cosmos/mint/v1beta1/inflation` returns the chain's current
        /// annualized inflation (`cosmos.Dec` string). LUNC's mint module is
        /// disabled — the endpoint returns 501 / "method not implemented"
        /// and the resolver collapses to a zero inflation, matching Windows.
        case mintInflation
        /// `/cosmos/staking/v1beta1/pool` returns the bonded/not-bonded
        /// supply totals in base units. Used together with the bank supply
        /// to derive `bondedRatio = bonded / totalSupply`.
        case stakingPool
        /// `/cosmos/bank/v1beta1/supply/by_denom?denom={denom}` — total
        /// supply of the bond denom in base units. Pair with the staking
        /// pool to derive `bondedRatio`.
        case bankSupplyByDenom(denom: String)
        /// `/cosmos/distribution/v1beta1/params` — community tax skim
        /// applied before per-validator commission.
        case distributionParams
    }

    var path: String {
        switch endpoint {
        case .delegations(let address):
            return "/cosmos/staking/v1beta1/delegations/\(address)"
        case .unbondingDelegations(let address):
            return "/cosmos/staking/v1beta1/delegators/\(address)/unbonding_delegations"
        case .delegatorRewards(let address):
            return "/cosmos/distribution/v1beta1/delegators/\(address)/rewards"
        case .bondedValidators:
            return "/cosmos/staking/v1beta1/validators"
        case .redelegations(let address):
            return "/cosmos/staking/v1beta1/delegators/\(address)/redelegations"
        case .mintInflation:
            return "/cosmos/mint/v1beta1/inflation"
        case .stakingPool:
            return "/cosmos/staking/v1beta1/pool"
        case .bankSupplyByDenom:
            return "/cosmos/bank/v1beta1/supply/by_denom"
        case .distributionParams:
            return "/cosmos/distribution/v1beta1/params"
        }
    }

    var method: HTTPMethod { .get }

    var task: HTTPTask {
        switch endpoint {
        case .bondedValidators:
            return .requestParameters(
                [
                    "status": "BOND_STATUS_BONDED",
                    "pagination.limit": 300
                ],
                .urlEncoding
            )
        case .bankSupplyByDenom(let denom):
            return .requestParameters(["denom": denom], .urlEncoding)
        default:
            return .requestPlain
        }
    }

    /// LCD GETs occasionally take longer than the default 60s when the
    /// validator list is freshly cold-cached. Bumping per-request is
    /// cheaper than retrying — and the user can pull-to-refresh.
    var timeoutInterval: TimeInterval { 30 }
}
