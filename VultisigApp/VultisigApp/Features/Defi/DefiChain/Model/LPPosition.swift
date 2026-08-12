//
//  LPPosition.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/10/2025.
//

import Foundation
import SwiftData

@Model
final class LPPosition {
    @Attribute(.unique) var id: String

    var coin1: CoinMeta
    var coin1Amount: Decimal
    var coin2: CoinMeta
    var coin2Amount: Decimal
    var poolName: String?
    var poolUnits: String?
    var apr: Double
    var lastUpdated: Date = Date.now

    @Relationship(inverse: \Vault.lpPositions) var vault: Vault?

    init(
        coin1: CoinMeta,
        coin1Amount: Decimal,
        coin2: CoinMeta,
        coin2Amount: Decimal,
        poolName: String,
        poolUnits: String,
        apr: Double,
        vault: Vault
    ) {
        self.coin1 = coin1
        self.coin1Amount = coin1Amount
        self.coin2 = coin2
        self.coin2Amount = coin2Amount
        self.apr = apr
        self.poolName = poolName
        self.poolUnits = poolUnits
        self.lastUpdated = Date.now
        self.vault = vault
        self.id = "\(coin1.chain.ticker)_\(coin1.contractAddress)_\(poolName)_\(vault.pubKeyECDSA)"
    }

    convenience init(_ dto: LPPositionData, vault: Vault) {
        self.init(
            coin1: dto.coin1,
            coin1Amount: dto.coin1Amount,
            coin2: dto.coin2,
            coin2Amount: dto.coin2Amount,
            poolName: dto.poolName,
            poolUnits: dto.poolUnits,
            apr: dto.apr,
            vault: vault
        )
    }

    /// Updates everything except the lookup key (`coin2`) and the persistent `id`.
    ///
    /// The equality guard is load-bearing, not an optimization. SwiftData's `@Model`
    /// setter wraps each store in `withMutation(of:)`, which notifies observers
    /// **without comparing** the new value to the old — so re-assigning a value that
    /// is already there still invalidates every SwiftUI view reading this position.
    /// A plain `@Observable` class does not behave this way, which is why the habit
    /// of assigning blind is safe elsewhere and not here. Since a refresh re-applies
    /// the same DTO whenever nothing moved on-chain, an unguarded `apply` re-dirties
    /// its readers on every single call; on macOS that feeds `NSHostingView`, which
    /// re-marks the window's constraints on each graph invalidation, and the pair can
    /// escalate into a layout loop that never converges.
    ///
    /// Two properties of the guard matter, and both were established by measurement:
    /// it must cover **every** write below including the `lastUpdated` stamp — a stamp
    /// left outside re-notifies by itself and defeats the guard entirely — and it must
    /// compare **every** field that is assigned, or an uncompared field re-opens the
    /// same hole. Add to both lists together.
    func apply(_ dto: LPPositionData) {
        guard coin1 != dto.coin1
            || coin1Amount != dto.coin1Amount
            || coin2Amount != dto.coin2Amount
            || poolName != dto.poolName
            || poolUnits != dto.poolUnits
            || apr != dto.apr
        else { return }

        coin1 = dto.coin1
        coin1Amount = dto.coin1Amount
        coin2Amount = dto.coin2Amount
        poolName = dto.poolName
        poolUnits = dto.poolUnits
        apr = dto.apr
        lastUpdated = .now
    }
}
