//
//  NativePoolEligibility.swift
//  VultisigApp
//
//  Pure, synchronous eligibility predicate for native (THORChain / MayaChain)
//  swap pools. Mirrors `SwapKitProviderCache.chainEnabled` — the caller supplies
//  a pool set (a live snapshot, the static fallback, or their union) and this
//  answers whether a vault coin is eligible.
//

import Foundation

enum NativePoolEligibility {

    /// Returns `true` iff `pools` contains an `Available` pool on the same
    /// chain and ticker, with a matching contract.
    ///
    /// Collision rule: when a pool carries a contract, the coin's contract must
    /// equal it (case-insensitive) — a coin cannot borrow another same-ticker
    /// coin's pool eligibility. When the pool has no contract (an L1 native,
    /// e.g. `ETH.ETH`) the match is ticker-only, since there is exactly one
    /// native per chain.
    static func isEligible(
        chain: Chain,
        ticker: String,
        contract: String?,
        in pools: [NativePoolAsset]
    ) -> Bool {
        let normalizedTicker = ticker.uppercased()
        let normalizedContract = contract?.lowercased()
        return pools.contains { pool in
            guard pool.isAvailable,
                  pool.poolChain == chain,
                  pool.ticker == normalizedTicker else {
                return false
            }
            guard let poolContract = pool.contract else {
                return true
            }
            return poolContract == normalizedContract
        }
    }
}
