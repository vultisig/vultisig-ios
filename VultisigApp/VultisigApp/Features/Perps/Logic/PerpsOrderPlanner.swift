//
//  PerpsOrderPlanner.swift
//  VultisigApp
//
//  Turns an order ticket into the exact Hyperliquid actions that
//  would be signed: an `updateLeverage` step first (the SDK contract requires
//  it to precede an open), then the `order`, optionally bracketed with
//  take-profit / stop-loss triggers (`normalTpsl`). Pure, so the review sheet
//  and tests see the same bytes a signer would.
//

import Foundation

struct PerpsTicket: Equatable, Sendable {
    var side: PerpsSide
    var margin: Decimal
    var leverage: Int
    var marginMode: PerpsMarginMode
    /// nil = market (IOC at mark ± slippage), otherwise a resting GTC limit.
    var limitPrice: Decimal?
    var takeProfit: Decimal?
    var stopLoss: Decimal?
    var slippage: Decimal = Decimal(string: "0.01") ?? 0
}

struct PerpsPlannedStep: Equatable, Sendable {
    enum Kind: String, Sendable {
        case updateLeverage = "update_leverage"
        case order
    }

    let kind: Kind
    let action: HLValue
    let nonce: UInt64

    /// The dry-run /exchange request, with a short `expiresAfter` so a signed
    /// but unsent step cannot be replayed later.
    var request: HLExchangeRequest? {
        try? HLExchangeRequest.l1(
            kind == .order ? .order : .updateLeverage,
            action: action,
            nonce: nonce,
            isMainnet: PerpsConfig.isMainnet,
            expiresAfter: nonce + HLNonceSource.defaultExpiryMs
        )
    }
}

struct PerpsOrderPlan: Equatable, Sendable {
    let market: PerpsMarket
    let ticket: PerpsTicket
    let estimate: PerpsOrderEstimate
    let price: Decimal
    let steps: [PerpsPlannedStep]

    var isMarket: Bool { ticket.limitPrice == nil }
    var requests: [HLExchangeRequest] { steps.compactMap(\.request) }
}

enum PerpsOrderPlannerError: Error, Equatable {
    case sizeTooSmall
    case leverageOutOfRange
    case isolatedOnly
    case minimumNotional
    case missingLimitPrice
}

enum PerpsOrderPlanner {
    /// Hyperliquid rejects orders under $10 notional.
    static let minimumNotional: Decimal = 10

    static func plan(
        market: PerpsMarket,
        ticket: PerpsTicket,
        nonce: UInt64,
        crossAccountValue: Decimal? = nil,
        builder: HLBuilderFee? = nil
    ) throws -> PerpsOrderPlan {
        guard ticket.leverage >= 1, ticket.leverage <= market.maxLeverage else { throw PerpsOrderPlannerError.leverageOutOfRange }
        if market.onlyIsolated && ticket.marginMode == .cross { throw PerpsOrderPlannerError.isolatedOnly }

        let reference = ticket.limitPrice ?? market.midPrice ?? market.markPrice
        let price = ticket.limitPrice.map { HLWireFormat.price($0, szDecimals: market.szDecimals) }
            ?? HLWireFormat.marketPrice(mid: reference, isBuy: ticket.side.isBuy, slippage: ticket.slippage, szDecimals: market.szDecimals)
        let estimate = PerpsMath.estimate(
            side: ticket.side,
            margin: ticket.margin,
            leverage: ticket.leverage,
            price: reference,
            szDecimals: market.szDecimals,
            maxLeverage: market.maxLeverage,
            marginMode: ticket.marginMode,
            crossAccountValue: crossAccountValue,
            schedule: market.marginSchedule
        )
        guard estimate.size > 0 else { throw PerpsOrderPlannerError.sizeTooSmall }
        guard estimate.notional >= minimumNotional else { throw PerpsOrderPlannerError.minimumNotional }

        let size = try HLWireFormat.wire(estimate.size)
        var orders = [HLOrderWire(
            asset: market.assetIndex,
            isBuy: ticket.side.isBuy,
            price: try HLWireFormat.wire(price),
            size: size,
            reduceOnly: false,
            type: .limit(ticket.limitPrice == nil ? .ioc : .gtc)
        )]
        for (trigger, kind) in [(ticket.takeProfit, HLOrderType.Kind.takeProfit), (ticket.stopLoss, .stopLoss)] {
            guard let trigger else { continue }
            let triggerPrice = try HLWireFormat.wire(HLWireFormat.price(trigger, szDecimals: market.szDecimals))
            orders.append(HLOrderWire(
                asset: market.assetIndex,
                isBuy: !ticket.side.isBuy,
                price: triggerPrice,
                size: size,
                reduceOnly: true,
                type: .trigger(isMarket: true, triggerPrice: triggerPrice, kind: kind)
            ))
        }
        let grouping: HLGrouping = orders.count > 1 ? .normalTpsl : .standalone
        let steps = [
            PerpsPlannedStep(
                kind: .updateLeverage,
                action: HLActions.updateLeverage(asset: market.assetIndex, isCross: ticket.marginMode == .cross, leverage: ticket.leverage),
                nonce: nonce
            ),
            PerpsPlannedStep(kind: .order, action: HLActions.order(orders, grouping: grouping, builder: builder), nonce: nonce + 1)
        ]
        return PerpsOrderPlan(market: market, ticket: ticket, estimate: estimate, price: price, steps: steps)
    }

    /// Plain-English summary for the review sheet, in the spirit of the SDK's `formatHlConfirmation`.
    static func summary(_ plan: PerpsOrderPlan) -> String {
        let ticket = plan.ticket
        let side = ticket.side == .long ? "perpsLong".localized : "perpsShort".localized
        let size = HLWireFormat.decimalString(plan.estimate.size)
        let priceText = plan.isMarket
            ? String(format: "perpsSummaryMarket".localized, HLWireFormat.decimalString(plan.price))
            : String(format: "perpsSummaryLimit".localized, HLWireFormat.decimalString(plan.price))
        let liquidation = plan.estimate.liquidationPrice.map { HLWireFormat.decimalString(HLWireFormat.price($0, szDecimals: plan.market.szDecimals)) } ?? "-"
        return String(
            format: "perpsSummarySentence".localized,
            side,
            size,
            plan.market.coin,
            "\(ticket.leverage)",
            ticket.marginMode == .cross ? "perpsCross".localized : "perpsIsolated".localized,
            HLWireFormat.decimalString(plan.estimate.margin.rounded(scale: 2)),
            priceText,
            liquidation
        )
    }
}

extension Decimal {
    func rounded(scale: Int, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var copy = self
        var result = Decimal()
        NSDecimalRound(&result, &copy, scale, mode)
        return result
    }
}
