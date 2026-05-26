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
        default:
            return .requestPlain
        }
    }

    /// LCD GETs occasionally take longer than the default 60s when the
    /// validator list is freshly cold-cached. Bumping per-request is
    /// cheaper than retrying — and the user can pull-to-refresh.
    var timeoutInterval: TimeInterval { 30 }
}
