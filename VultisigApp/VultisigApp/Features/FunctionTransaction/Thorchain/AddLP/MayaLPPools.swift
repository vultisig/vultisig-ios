//
//  MayaLPPools.swift
//  VultisigApp
//
//  Which MayaChain pools the app pairs, and which pool each chain's native
//  coin deposits into.
//
//  A paired CACAO add credits nothing until the matching asset deposit
//  arrives, and MayaChain refunds it if that never happens. So the CACAO side
//  names an asset address only for pools whose asset half can be sent from
//  here; every other pool stays a single-sided add.
//

import Foundation

enum MayaLPPools {

    /// The pool a chain's native coin deposits into from the Functions action.
    static let nativePools: [Chain: String] = [
        .bitcoin: "BTC.BTC",
        .ethereum: "ETH.ETH",
        .arbitrum: "ARB.ETH",
        .dash: "DASH.DASH",
        .zcash: "ZEC.ZEC"
    ]

    static func nativePool(for chain: Chain) -> String? {
        nativePools[chain]
    }

    /// The chain that holds the asset half of `pool`, when the app can send it.
    /// ERC-20 pools resolve to their EVM chain: those deposits go through the
    /// router.
    static func assetChain(ofPool pool: String) -> Chain? {
        let prefix = pool.split(separator: ".", maxSplits: 1).first.map { String($0).uppercased() }
        guard let prefix, pool.contains(".") else { return nil }
        return nativePools.keys.first { $0.swapAsset.uppercased() == prefix }
    }

    static func isPairable(pool: String) -> Bool {
        assetChain(ofPool: pool) != nil
    }
}
