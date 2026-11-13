//
//  PerpsMath.swift
//  VultisigApp
//
//  Pure order-ticket math. Liquidation follows Hyperliquid's
//  documented formula (trading/liquidations, margining, margin-tiers):
//    liq = price - side * marginAvailable / size / (1 - l * side)
//    l   = 1 / (2 * maxLeverage(tier))
//    maintenance(tier) = notional * mmr(tier) - deduction(tier)
//    deduction(0) = 0, deduction(n) = deduction(n-1) + lowerBound(n) * (mmr(n) - mmr(n-1))
//  with the tier picked from the position value AT the liquidation price.
//  Pre-trade estimates only; once open, the venue's `liquidationPx` wins.
//

import Foundation

enum PerpsSide: String, Sendable, CaseIterable {
    case long
    case short

    var sign: Decimal { self == .long ? 1 : -1 }
    var isBuy: Bool { self == .long }
}

enum PerpsMarginMode: String, Sendable {
    case cross
    case isolated
}

struct PerpsMarginTier: Equatable, Hashable, Sendable {
    let lowerBound: Decimal
    let maxLeverage: Int

    var maintenanceRate: Decimal { maxLeverage > 0 ? 1 / Decimal(2 * maxLeverage) : 0 }
}

/// A market's margin table. Ids below 50 are a single tier at that leverage.
struct PerpsMarginSchedule: Equatable, Sendable {
    let tiers: [PerpsMarginTier]

    init(tiers: [PerpsMarginTier], fallbackMaxLeverage: Int) {
        let sorted = tiers.sorted { $0.lowerBound < $1.lowerBound }
        self.tiers = sorted.isEmpty ? [PerpsMarginTier(lowerBound: 0, maxLeverage: fallbackMaxLeverage)] : sorted
    }

    static func single(maxLeverage: Int) -> PerpsMarginSchedule {
        PerpsMarginSchedule(tiers: [], fallbackMaxLeverage: maxLeverage)
    }

    func deduction(tier index: Int) -> Decimal {
        guard index > 0 else { return 0 }
        return (1...index).reduce(Decimal(0)) { total, tier in
            total + tiers[tier].lowerBound * (tiers[tier].maintenanceRate - tiers[tier - 1].maintenanceRate)
        }
    }

    func tierIndex(notional: Decimal) -> Int {
        tiers.lastIndex { $0.lowerBound <= notional } ?? 0
    }

    func maintenanceMargin(notional: Decimal) -> Decimal {
        let index = tierIndex(notional: notional)
        return notional * tiers[index].maintenanceRate - deduction(tier: index)
    }
}

struct PerpsOrderEstimate: Equatable, Sendable {
    let size: Decimal
    let notional: Decimal
    let margin: Decimal
    let liquidationPrice: Decimal?
    let fee: Decimal
}

enum PerpsMath {
    /// Taker fee for the base tier (0.045%), used for the ticket's estimate.
    static let baseTakerFeeRate: Decimal = Decimal(string: "0.00045") ?? 0

    static func maintenanceRate(maxLeverage: Int) -> Decimal {
        guard maxLeverage > 0 else { return 0 }
        return 1 / (Decimal(2 * maxLeverage))
    }

    /// Size bought by `margin` at `leverage`, rounded down to the asset's lot size.
    static func size(margin: Decimal, leverage: Int, price: Decimal, szDecimals: Int) -> Decimal {
        guard price > 0, leverage > 0, margin > 0 else { return 0 }
        return HLWireFormat.size(margin * Decimal(leverage) / price, szDecimals: szDecimals)
    }

    static func notional(size: Decimal, price: Decimal) -> Decimal { size * price }

    static func requiredMargin(notional: Decimal, leverage: Int) -> Decimal {
        guard leverage > 0 else { return 0 }
        return notional / Decimal(leverage)
    }

    /// Liquidation price of a position given the collateral that backs it.
    /// For isolated margin `collateral` is the position's margin; for cross it
    /// is the account value available to this position, which is why the cross
    /// estimate does not move with the leverage setting.
    static func liquidationPrice(
        side: PerpsSide,
        entryPrice: Decimal,
        size: Decimal,
        collateral: Decimal,
        maxLeverage: Int
    ) -> Decimal? {
        liquidationPrice(side: side, entryPrice: entryPrice, size: size, collateral: collateral,
                         schedule: .single(maxLeverage: maxLeverage))
    }

    /// Solves `collateral + side * size * (P - entry) = maintenance(size * P)`
    /// tier by tier, keeping the tier that contains the notional at P.
    static func liquidationPrice(
        side: PerpsSide,
        entryPrice: Decimal,
        size: Decimal,
        collateral: Decimal,
        schedule: PerpsMarginSchedule
    ) -> Decimal? {
        guard size > 0, entryPrice > 0 else { return nil }
        let candidates = schedule.tiers.indices.reversed().compactMap { index -> (Int, Decimal)? in
            let rate = schedule.tiers[index].maintenanceRate
            let denominator = size * (rate - side.sign)
            guard denominator != 0 else { return nil }
            let price = (collateral - side.sign * size * entryPrice + schedule.deduction(tier: index)) / denominator
            return (index, price)
        }
        let match = candidates.first { schedule.tierIndex(notional: size * $0.1) == $0.0 } ?? candidates.last
        guard let price = match?.1, price > 0 else { return nil }
        return price
    }

    /// Funding is paid hourly. Positive = this position pays, negative = it earns.
    static func dailyFundingCost(side: PerpsSide, notional: Decimal, hourlyRate: Decimal) -> Decimal {
        notional * hourlyRate * 24 * side.sign
    }

    static func estimate(
        side: PerpsSide,
        margin: Decimal,
        leverage: Int,
        price: Decimal,
        szDecimals: Int,
        maxLeverage: Int,
        marginMode: PerpsMarginMode,
        crossAccountValue: Decimal? = nil,
        schedule: PerpsMarginSchedule? = nil
    ) -> PerpsOrderEstimate {
        let size = size(margin: margin, leverage: leverage, price: price, szDecimals: szDecimals)
        let notional = notional(size: size, price: price)
        let usedMargin = requiredMargin(notional: notional, leverage: leverage)
        let collateral = marginMode == .cross ? max(usedMargin, crossAccountValue ?? usedMargin) : usedMargin
        let liquidation = liquidationPrice(side: side, entryPrice: price, size: size, collateral: collateral,
                                           schedule: schedule ?? .single(maxLeverage: maxLeverage))
        return PerpsOrderEstimate(size: size, notional: notional, margin: usedMargin, liquidationPrice: liquidation, fee: notional * baseTakerFeeRate)
    }

    static func unrealizedPnl(side: PerpsSide, entryPrice: Decimal, markPrice: Decimal, size: Decimal) -> Decimal {
        (markPrice - entryPrice) * size * side.sign
    }

    /// Hyperliquid funding is paid hourly; the ticket shows the annualised rate.
    static func annualizedFunding(hourlyRate: Decimal) -> Decimal { hourlyRate * 24 * 365 }

    /// Percentage move between two prices, e.g. 24h change.
    static func percentChange(from previous: Decimal, to current: Decimal) -> Decimal {
        guard previous != 0 else { return 0 }
        return (current - previous) / previous * 100
    }

    /// Distance to liquidation in percent of the mark, a calmer number for the UI than a raw price.
    static func liquidationDistance(markPrice: Decimal, liquidationPrice: Decimal) -> Decimal {
        guard markPrice > 0 else { return 0 }
        let delta = markPrice - liquidationPrice
        return (delta < 0 ? -delta : delta) / markPrice * 100
    }
}
