//
//  BondInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/11/2025.
//

/// The vault state a bond fetch needs, read once on the main actor.
///
/// `Vault` and `Coin` are SwiftData `@Model` classes, so the `nonisolated`
/// fetch below must never touch them directly; it carries this value type
/// through the network work instead.
struct BondCoinSnapshot: Sendable {
    let meta: CoinMeta
    let address: String
}

protocol BondInteractor {
    func fetchBondPositions(vault: Vault) async throws -> (active: [BondPosition], available: [BondNode])
    func canUnbond() async -> Bool
    func canAddBond() async -> Bool
}
