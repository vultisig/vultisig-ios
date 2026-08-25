//
//  SwapKitChainIdentifier.swift
//  VultisigApp
//
//  Translation from the Vultisig `Chain` enum to the chainId string SwapKit's
//  `/track` endpoint expects. EVM chains use their decimal chainId directly;
//  non-EVM chains use SwapKit's slug.
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
