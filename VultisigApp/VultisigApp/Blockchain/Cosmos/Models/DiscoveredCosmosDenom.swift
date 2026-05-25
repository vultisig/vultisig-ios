//
//  DiscoveredCosmosDenom.swift
//  VultisigApp
//
//  Value type returned by `CosmosCoinFinder.discoverBankDenoms`. Carries the
//  resolved metadata for one bank denom held at a Terra / TerraClassic
//  address. Mirrors the SDK `DiscoveredToken` shape with the `isHidden` flag
//  preserved — wallets that consume this type decide whether to auto-add the
//  denom to the visible coin list (`isHidden = false`) or only surface it
//  through Manage Tokens (`isHidden = true`).
//

import Foundation

struct DiscoveredCosmosDenom: Equatable {
    let denom: String
    let ticker: String
    let decimals: Int
    let logo: String
    let priceProviderId: String
    let isHidden: Bool
}
