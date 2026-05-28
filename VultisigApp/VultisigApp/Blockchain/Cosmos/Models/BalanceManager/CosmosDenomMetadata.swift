//
//  CosmosDenomMetadata.swift
//  VultisigApp
//
//  Mirrors the Cosmos REST `bank/v1beta1/denoms_metadata` response shape
//  used by `CosmosTokenMetadataResolver` to derive ticker + decimals for
//  arbitrary held bank denoms (IBC-wrapped tokens, factory tokens, etc.).
//
//  The SDK's `getBankDenomMetadata` fallback chain (denoms_metadata/{denom}
//  → denoms_metadata?pagination.limit=1000 → IBC trace recursion) consumes
//  this exact shape — see `vultisig-sdk/packages/core/chain/coin/token/
//  metadata/resolvers/cosmos.ts`.
//
//  All fields are optional because chain LCDs are inconsistent in what they
//  populate. The resolver handles missing `display` / `denom_units` by
//  falling through to the next tier of the fallback chain.
//

import Foundation

/// Single entry in `denom_units` — the wallet picks the unit whose `denom`
/// matches `display` (or `symbol`) and reports its `exponent` as the asset's
/// decimal places. See `decimalsFromMeta` for the disambiguation rule.
struct CosmosDenomUnit: Decodable, Equatable {
    let denom: String
    let exponent: Int
}

/// Metadata payload for a single bank denom. Mirrors the SDK `DenomMetadata`
/// type byte-for-byte — `base` carries the on-chain denom id, `display` /
/// `symbol` pick the human unit, and `denom_units` carries the conversion
/// table.
struct CosmosDenomMetadata: Decodable, Equatable {
    let base: String?
    let symbol: String?
    let display: String?
    let denomUnits: [CosmosDenomUnit]?

    enum CodingKeys: String, CodingKey {
        case base
        case symbol
        case display
        case denomUnits = "denom_units"
    }
}

/// Response envelope for `/cosmos/bank/v1beta1/denoms_metadata/{denom}`.
struct CosmosDenomMetadataResponse: Decodable {
    let metadata: CosmosDenomMetadata?
}

/// Response envelope for `/cosmos/bank/v1beta1/denoms_metadata?pagination.limit=N`.
struct CosmosDenomMetadatasResponse: Decodable {
    let metadatas: [CosmosDenomMetadata]?
}
