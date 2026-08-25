//
//  SwapKitChainIdentifier.swift
//  VultisigApp
//
//  Translation from the Vultisig `Chain` enum to the chainId string SwapKit's
//  `/track` endpoint expects. The table mirrors the canonical chain table in
//  `swapkit-spike/api-contract.md` — EVM chains use the decimal chainId,
//  non-EVM chains use SwapKit's slug.
//
//  Kept separate from `SwapKitService.chainPrefix` because that function maps
//  to the *asset prefix* (e.g. `ETH`, `ARB`, `BTC`) — `/track` needs the
//  numeric/slug chainId instead, which only overlaps for a couple of chains.
//

import Foundation

enum SwapKitChainIdentifier {
    /// Returns the chainId string SwapKit's `/track` endpoint expects, or
    /// `nil` for chains that are not part of the SwapKit route catalogue.
    /// `nil` is the signal to skip tracking — the caller surfaces a deep-link
    /// fallback rather than attempting polling against an unknown chain.
    static func chainId(for chain: Chain) -> String? {
        let chainId = SwapKitChainIDMapper.swapKitChainId(for: chain)
        return chainId.isEmpty ? nil : chainId
    }
}
