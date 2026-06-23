//
//  CustomRPCSupportedChains.swift
//  VultisigApp
//

import Foundation

/// Single source of truth for the chains whose RPC endpoint can be overridden.
///
/// The resolution funnel (EVM / Cosmos / THORChain / Solana service configs) and
/// the custom-RPC settings UI both read this list so they can never disagree:
/// a chain shown in the picker is exactly a chain the funnel honors.
///
/// UTXO chains are intentionally excluded — they route balance/broadcast through
/// the `api.vultisig.com` proxy (Blockchair / Bitcoin / Dash proxies) rather
/// than a raw node RPC, so a user-supplied node URL has no coherent insertion
/// point. See the PR description for the full rationale.
enum CustomRPCSupportedChains {

    /// Chains exposed in the custom-RPC settings list, grouped by family and in a
    /// stable display order.
    static let all: [Chain] = [
        // EVM
        .ethereum,
        .ethereumSepolia,
        .bscChain,
        .avalanche,
        .base,
        .arbitrum,
        .polygon,
        .optimism,
        .blast,
        .cronosChain,
        .zksync,
        .mantle,
        .hyperliquid,
        .sei,
        // Solana
        .solana,
        // THORChain family (mayaChain rides the THORChain LCD funnel)
        .thorChain,
        .mayaChain,
        // Cosmos
        .gaiaChain,
        .dydx,
        .kujira,
        .osmosis,
        .terra,
        .terraClassic,
        .noble,
        .akash,
        // Real-node single-RPC chains
        .ripple,
        .sui,
        .bittensor,
        // Proxy-default chains: an override swaps only the host; the proxy
        // request paths stay unchanged, so default users are byte-identical.
        .tron,
        .ton,
        .polkadot
    ]

    static func isSupported(_ chain: Chain) -> Bool {
        all.contains(chain)
    }
}
