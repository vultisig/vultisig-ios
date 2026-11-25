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
    /// This bond address's realized reward at each churn of its current bond,
    /// newest first — powers the Total Rewards Earned sheet. Rewards already
    /// loaded once are kept on the device and served from there, so the
    /// history reaches further back than the node's own retained state.
    func fetchRewardHistory(nodeAddress: String, myBondAddress: String) async throws -> [BondRewardHistoryEntry]
    /// The chain's bond address for `vault` — what `fetchRewardHistory`
    /// calls `myBondAddress`. `nil` when the vault has no coin for this
    /// chain, mirroring `fetchBondPositions`'s own early-return guard.
    func bondCoinAddress(in vault: Vault) async -> String?
}
