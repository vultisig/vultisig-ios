//
//  LPPositionData.swift
//  VultisigApp
//
//  Sendable value-type DTO mirror of `LPPosition` (`@Model`).
//  See `StakePositionData` for the rationale.
//

import Foundation

struct LPPositionData: Sendable, Equatable {
    let coin1: CoinMeta
    let coin1Amount: Decimal
    let coin2: CoinMeta
    let coin2Amount: Decimal
    let poolName: String
    let poolUnits: String
    let apr: Double
}
