//
//  CosmosChainApyDTOs.swift
//  VultisigApp
//
//  Wire shapes + value types for the 4 LCD endpoints that feed the
//  on-chain APY computation:
//
//    /cosmos/mint/v1beta1/inflation         → MintInflationResponse
//    /cosmos/staking/v1beta1/pool           → StakingPoolResponse
//    /cosmos/bank/v1beta1/supply/by_denom   → BankSupplyResponse
//    /cosmos/distribution/v1beta1/params    → DistributionParamsResponse
//
//  Formula (mirrors `core/ui/chain/cosmos/apr/` on Windows):
//
//    apy = (1 − communityTax) × (inflation / bondedRatio) × (1 − commission)
//
//  with `bondedRatio = bondedTokens / totalSupply`. Inputs clamp to [0,1];
//  zero inflation or zero bonded ratio collapses APY to nil so the row
//  hides per the Windows behavior.
//

import Foundation

/// Aggregated, denom-aware APY inputs for a chain. The per-validator APY
/// multiplier is applied downstream — this struct is the chain-level
/// constant cached for 5 minutes.
struct CosmosChainApyData: Equatable, Sendable {
    /// Annual inflation rate, clamped to `[0, 1]`. Zero on chains whose
    /// mint module is disabled (e.g. LUNC columbus-5).
    let inflation: Decimal
    /// Bonded tokens divided by total supply, clamped to `[0, 1]`.
    let bondedRatio: Decimal
    /// Community-pool skim taken before per-validator commission.
    let communityTax: Decimal
}

// MARK: - Mint inflation

struct CosmosMintInflationResponse: Decodable {
    /// `cosmos.Dec` string — e.g. `"0.070000000000000000"`. Parsed via
    /// `Decimal(string:)` in the resolver.
    let inflation: String
}

// MARK: - Staking pool

struct CosmosStakingPoolResponse: Decodable {
    let pool: Pool

    struct Pool: Decodable {
        let notBondedTokens: String
        let bondedTokens: String

        enum CodingKeys: String, CodingKey {
            case notBondedTokens = "not_bonded_tokens"
            case bondedTokens = "bonded_tokens"
        }
    }
}

// MARK: - Bank supply by denom

struct CosmosBankSupplyResponse: Decodable {
    let amount: CosmosStakingCoin
}

// MARK: - Distribution params

struct CosmosDistributionParamsResponse: Decodable {
    let params: Params

    struct Params: Decodable {
        /// `cosmos.Dec` string. LUNC has historically returned 0% community
        /// tax; LUNA varies with gov proposals.
        let communityTax: String

        enum CodingKeys: String, CodingKey {
            case communityTax = "community_tax"
        }
    }
}
