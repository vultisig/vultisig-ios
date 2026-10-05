//
//  MayaLPChecks.swift
//  VultisigApp
//
//  What a MayaChain LP add reads from the node before it is signed. A struct of
//  closures so the form's rules can be driven without a network.
//

import Foundation

struct MayaLPChecks {
    /// The vault's record on `pool`, or nil when the node has none. Throws when
    /// the record cannot be read.
    var liquidityProvider: (_ pool: String, _ cacaoAddress: String) async throws -> MayaLiquidityProvider?

    static let live = MayaLPChecks(
        liquidityProvider: { pool, cacaoAddress in
            try await MayaChainAPIService().getLiquidityProvider(pool: pool, address: cacaoAddress)
        }
    )
}
