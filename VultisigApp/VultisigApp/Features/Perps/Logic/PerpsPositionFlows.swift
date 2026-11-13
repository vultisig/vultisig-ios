//
//  PerpsPositionFlows.swift
//  VultisigApp
//
//  Perps withdraw quote, isolated margin add / remove, partial close
//  by fraction, and the outcome of a closed position (stop, take profit,
//  liquidation). Pure: the sheets, the review documents and the tests all
//  call these, so every screen shows the same numbers.
//

import Foundation

// MARK: - Withdraw

/// What a withdrawal costs and delivers. The amount is capped by the server's
/// `withdrawable`, never equity: open positions keep margin back.
struct PerpsWithdrawQuote: Equatable, Sendable {
    let amount: Decimal
    let withdrawable: Decimal
    /// withdraw3's flat fee, charged by Hyperliquid.
    let fee: Decimal
    /// One-time account activation, 0 once it has been paid.
    let activationFee: Decimal

    var totalFees: Decimal { fee + activationFee }
    var receive: Decimal { max(0, amount - totalFees) }

    enum Issue: Equatable, Sendable { case moreThanWithdrawable, belowFees }

    var issue: Issue? {
        guard amount > 0 else { return nil }
        if amount > withdrawable { return .moreThanWithdrawable }
        if amount <= totalFees { return .belowFees }
        return nil
    }

    static func make(amount: Decimal, account: PerpsAccountSnapshot) -> PerpsWithdrawQuote {
        PerpsWithdrawQuote(
            amount: amount,
            withdrawable: account.availableToWithdraw,
            fee: PerpsConfig.withdrawFee,
            activationFee: PerpsConfig.withdrawActivationFee(hasWithdrawnBefore: account.hasWithdrawnBefore)
        )
    }
}

/// Trading account sheet: two numbers that add up to the equity on the
/// hub. "In positions" is never called margin (it includes open P&L).
struct PerpsAccountSummary: Equatable, Sendable {
    let available: Decimal
    let inPositions: Decimal

    static func make(_ account: PerpsAccountSnapshot) -> PerpsAccountSummary {
        PerpsAccountSummary(available: account.availableToTrade, inPositions: max(0, account.equity - account.availableToTrade))
    }
}

extension PerpsConfig {
    /// UNCERTAIN. Circle's CCTP guide charges 1 USDC to
    /// activate a new HyperCore account on its first outbound action; the spike
    /// read it as the first inbound one, and Hyperliquid's docs tie it to a new
    /// destination, maybe not to `withdraw3` at all. Perps shows it on the
    /// first withdrawal (the conservative "you receive"). `nil` history counts
    /// as first. If live testing shows no charge, set this to 0: the screens
    /// and the footnote follow the quote.
    static let withdrawActivationFeeAmount: Decimal = 1

    static func withdrawActivationFee(hasWithdrawnBefore: Bool?) -> Decimal {
        hasWithdrawnBefore == true ? 0 : withdrawActivationFeeAmount
    }
}

// MARK: - Isolated margin

struct PerpsMarginChange: Equatable, Sendable {
    /// Signed USD: positive adds, negative removes.
    let delta: Decimal
    let marginBefore: Decimal
    let liquidationBefore: Decimal?
    let liquidationAfter: Decimal?
    let availableBefore: Decimal
    let maxRemovable: Decimal

    var marginAfter: Decimal { marginBefore + delta }
    var availableAfter: Decimal { availableBefore - delta }

    enum Issue: Equatable, Sendable { case crossPosition, moreThanAvailable, moreThanRemovable }

    var issue: Issue?
}

enum PerpsMarginFlows {
    /// The margin the user put in: isolated `marginUsed` includes uPnL, which
    /// is shown as P&L instead, so it is taken out. The position screen, Modify,
    /// the margin review and the outcomes all show this one number.
    static func margin(of position: HLPosition) -> Decimal {
        position.leverage.isCross ? position.marginUsed.value : position.marginUsed.value - position.unrealizedPnl.value
    }

    /// Margin that can leave an isolated position: Hyperliquid keeps
    /// `max(initial margin, 10% of position value)` (spec, margining). Cents, rounded down.
    static func maxRemovable(position: HLPosition, markPrice: Decimal) -> Decimal {
        guard !position.leverage.isCross, position.leverage.value > 0 else { return 0 }
        let value = abs(position.szi.value) * markPrice
        let required = max(value / Decimal(position.leverage.value), value / 10)
        return max(0, position.marginUsed.value - required).rounded(scale: 2, mode: .down)
    }

    /// The new liquidation price after `delta`. The formula's collateral is
    /// the margin at entry (isolated `marginUsed` includes uPnL, so it is taken
    /// out). The move is applied to the venue's own figure, so "before" is the
    /// number the position screen shows and "after" moves by exactly the formula's step.
    static func change(position: HLPosition, market: PerpsMarket, account: PerpsAccountSnapshot, delta: Decimal) -> PerpsMarginChange {
        let side: PerpsSide = position.isLong ? .long : .short
        let size = abs(position.szi.value)
        let entry = position.entryPx?.value ?? market.markPrice
        let collateral = margin(of: position)
        let formulaBefore = PerpsMath.liquidationPrice(side: side, entryPrice: entry, size: size, collateral: collateral,
                                                       schedule: market.marginSchedule)
        let formulaAfter = PerpsMath.liquidationPrice(side: side, entryPrice: entry, size: size, collateral: collateral + delta,
                                                      schedule: market.marginSchedule)
        let before = position.liquidationPx?.value ?? formulaBefore
        var after: Decimal?
        if let before, let formulaBefore, let formulaAfter {
            let shifted = before + (formulaAfter - formulaBefore)
            after = shifted > 0 ? shifted : nil
        }
        let removable = maxRemovable(position: position, markPrice: market.markPrice)
        var change = PerpsMarginChange(delta: delta, marginBefore: margin(of: position), liquidationBefore: before,
                                       liquidationAfter: delta == 0 ? before : after,
                                       availableBefore: account.availableToTrade, maxRemovable: removable)
        if position.leverage.isCross {
            change.issue = .crossPosition
        } else if delta > account.availableToTrade {
            change.issue = .moreThanAvailable
        } else if -delta > removable {
            change.issue = .moreThanRemovable
        }
        return change
    }

    /// `updateIsolatedMargin` (L1, signed by the trading account), reviewed in the shared sheet.
    static func review(position: HLPosition, market: PerpsMarket, change: PerpsMarginChange, nonce: UInt64) throws -> PerpsReviewDocument {
        let action = HLActions.updateIsolatedMargin(asset: market.assetIndex, usd: change.delta)
        let request = try HLExchangeRequest.l1(.updateIsolatedMargin, action: action, nonce: nonce, isMainnet: PerpsConfig.isMainnet,
                                               expiresAfter: nonce + HLNonceSource.defaultExpiryMs)
        let isAdd = change.delta >= 0
        let magnitude = isAdd ? change.delta : -change.delta
        return PerpsReviewDocument(
            sheetTitle: "perpsReview".localized,
            amountLabel: isAdd ? "perpsAddMargin".localized : "perpsRemoveMargin".localized,
            amount: PerpsFormat.amount(magnitude),
            caption: PerpsCloseFlows.positionCaption(position),
            coin: market.coin,
            rows: [
                PerpsReviewRow(label: "perpsMargin".localized, value: arrow(PerpsFormat.usd(change.marginBefore), PerpsFormat.usd(change.marginAfter))),
                PerpsReviewRow(label: "perpsLiquidation".localized,
                               value: arrow(change.liquidationBefore.map(PerpsFormat.price) ?? "perpsNone".localized,
                                            change.liquidationAfter.map(PerpsFormat.price) ?? "perpsNone".localized)),
                PerpsReviewRow(label: "perpsAvailableToTrade".localized,
                               value: arrow(PerpsFormat.usd(change.availableBefore), PerpsFormat.usd(change.availableAfter)))
            ],
            requests: [request],
            blockingIssue: change.delta == 0 ? "perpsNoChanges".localized : nil
        )
    }

    static func arrow(_ before: String, _ after: String) -> String { "\(before) \u{2192} \(after)" }
}

// MARK: - Partial close

enum PerpsCloseFraction: Int, CaseIterable, Identifiable, Sendable {
    case quarter = 25
    case half = 50
    case all = 100

    var id: Int { rawValue }
    /// "25%", "50%", "All": All closes the exact position, so it is not a percentage.
    var title: String { self == .all ? "perpsAll".localized : "\(rawValue)%" }

    /// Size to close, rounded down to the lot size. 100% is the whole
    /// position exactly, so nothing is left behind by rounding.
    func size(of total: Decimal, szDecimals: Int) -> Decimal {
        self == .all ? total : HLWireFormat.size(total * Decimal(rawValue) / 100, szDecimals: szDecimals)
    }

    /// A chip whose lot-rounded size is 0 cannot close anything.
    func isAvailable(total: Decimal, szDecimals: Int) -> Bool { size(of: total, szDecimals: szDecimals) > 0 }
}

enum PerpsCloseFlows {
    /// "BTC long · 2×"
    static func positionCaption(_ position: HLPosition) -> String {
        let side = position.isLong ? "perpsLong".localized : "perpsShort".localized
        return "\(position.coin) \(side) · \(position.leverage.value)×"
    }

    /// P&L after the closing fee: the hero number on the close sheet and its review.
    static func netProfit(_ estimate: PerpsFlows.CloseEstimate) -> Decimal { estimate.realizedPnl - estimate.fees }

    /// "0.00074 BTC". With `szDecimals`, padded to the lot size ("0.00050 BTC"),
    /// so sizes listed together line up.
    static func sizeText(_ size: Decimal, coin: String, szDecimals: Int? = nil) -> String {
        guard let szDecimals else { return "\(HLWireFormat.decimalString(size)) \(coin)" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumIntegerDigits = 1
        formatter.minimumFractionDigits = szDecimals
        formatter.maximumFractionDigits = szDecimals
        return "\(formatter.string(from: NSDecimalNumber(decimal: size)) ?? HLWireFormat.decimalString(size)) \(coin)"
    }

    /// The same position after `closed` of it left: size, value, P&L and
    /// margin scale down together, entry and liquidation stay (isolated margin
    /// leaves with the closed part). The position screen shows this while a
    /// partial result is open, so no number disagrees with the sheet.
    static func remaining(after closed: Decimal, of position: HLPosition) -> HLPosition {
        let total = abs(position.szi.value)
        guard total > 0 else { return position }
        let left = max(0, total - closed)
        let scale = left / total
        return HLPosition(
            coin: position.coin, szi: HLDecimal(position.isLong ? left : -left), leverage: position.leverage, entryPx: position.entryPx,
            positionValue: HLDecimal(position.positionValue.value * scale), unrealizedPnl: HLDecimal(position.unrealizedPnl.value * scale),
            returnOnEquity: position.returnOnEquity, liquidationPx: left > 0 ? position.liquidationPx : nil,
            marginUsed: HLDecimal(position.marginUsed.value * scale), maxLeverage: position.maxLeverage, cumFunding: position.cumFunding
        )
    }
}

// MARK: - Partly filled close

/// A reduce-only IOC that filled less than it asked for (`filled < requested`).
/// Every amount is kept at full precision and rounded once, for display.
struct PerpsPartialFill: Equatable, Sendable {
    let coin: String
    let total: Decimal
    let requested: Decimal
    let filled: Decimal
    let fillPrice: Decimal
    let fees: Decimal
    /// Profit after fees on the filled part.
    let netPnl: Decimal
    /// Margin put in for the filled part plus `netPnl`.
    let returned: Decimal

    var notClosed: Decimal { max(0, requested - filled) }
    var stillOpen: Decimal { max(0, total - filled) }

    static func make(position: HLPosition, requested: Decimal, filled: Decimal, fillPrice: Decimal) -> PerpsPartialFill {
        let total = abs(position.szi.value)
        let filled = min(filled, requested, total)
        let side: PerpsSide = position.isLong ? .long : .short
        let entry = position.entryPx?.value ?? fillPrice
        let gross = PerpsMath.unrealizedPnl(side: side, entryPrice: entry, markPrice: fillPrice, size: filled)
        let fees = filled * fillPrice * (PerpsMath.baseTakerFeeRate + PerpsConfig.builderFeeRate)
        let net = gross - fees
        let share = total > 0 ? PerpsMarginFlows.margin(of: position) * filled / total : 0
        return PerpsPartialFill(coin: position.coin, total: total, requested: requested, filled: filled, fillPrice: fillPrice,
                                fees: fees, netPnl: net, returned: max(0, share + net))
    }
}

// MARK: - Stop loss / take profit after a partial close

enum PerpsTriggerCoverage {
    /// Position TP/SL (`isPositionTpsl`, size 0) follow the position, so they
    /// always cover what is left. A fixed-size reduce-only trigger smaller than
    /// the position leaves part of it unprotected; a larger one cannot flip it
    /// (reduce-only), so only the smaller case warns.
    static func uncovered(triggers: [HLFrontendOrder], positionSize: Decimal) -> HLFrontendOrder? {
        triggers.first { order in
            order.isPositionTpsl != true && order.sz.value > 0 && order.sz.value < positionSize
        }
    }
}

// MARK: - Pending withdrawal

/// A withdrawal that left the trading account and has not reached the vault.
/// Kept across launches so the hub can say it is taking longer than usual.
struct PerpsPendingWithdrawal: Codable, Equatable, Sendable {
    let amount: Decimal
    let receive: Decimal
    let startedAt: Date
    /// The trading account it left, lowercased: a record never shows on another vault.
    var account: String = ""
    /// Written by the debug demo; never shown outside it.
    var isDemo = false

    /// No arrival after ten minutes reads as slow.
    static let slowAfter: TimeInterval = 600

    func isSlow(now: Date = Date()) -> Bool { now.timeIntervalSince(startedAt) >= Self.slowAfter }
    func minutesAgo(now: Date = Date()) -> Int { max(1, Int(now.timeIntervalSince(startedAt) / 60)) }
}

enum PerpsPendingWithdrawalStore {
    static let key = "perpsPendingWithdrawal"

    /// The pending withdrawal for this trading account, if any. Demo records
    /// only come back when the caller is the demo.
    static func load(account: String, includeDemo: Bool = false, _ defaults: UserDefaults = .standard) -> PerpsPendingWithdrawal? {
        guard let pending = defaults.data(forKey: key).flatMap({ try? JSONDecoder().decode(PerpsPendingWithdrawal.self, from: $0) }),
              pending.account == account.lowercased(), !pending.isDemo || includeDemo else { return nil }
        return pending
    }

    static func save(_ pending: PerpsPendingWithdrawal, _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(pending) { defaults.set(data, forKey: key) }
    }

    static func clear(_ defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }
}

// MARK: - Outcomes

/// A position closed by the venue (stop, take profit, liquidation), for the
/// outcome sheet. Live: built from `userFills` (`fromFills`); the debug demo
/// builds it from the position and a fill price.
struct PerpsOutcome: Equatable, Sendable {
    enum Kind: String, Sendable { case stopLoss, takeProfit, liquidated }

    let kind: Kind
    let coin: String
    let isLong: Bool
    let leverage: Int
    let triggerPrice: Decimal?
    let fillPrice: Decimal
    let size: Decimal
    let fees: Decimal
    /// After fees.
    let netPnl: Decimal
    /// Margin at entry, the base of the return percentage.
    let margin: Decimal

    /// What lands back in the trading account (0 for a backstop liquidation).
    var returned: Decimal { max(0, margin + netPnl) }
    var returnOnMargin: Decimal { margin > 0 ? netPnl / margin : 0 }

    /// Liquidations pay the taker fee only; stops and take profits also carry the builder fee.
    static func make(kind: Kind, position: HLPosition, fillPrice: Decimal, triggerPrice: Decimal?) -> PerpsOutcome {
        let size = abs(position.szi.value)
        let entry = position.entryPx?.value ?? fillPrice
        let side: PerpsSide = position.isLong ? .long : .short
        let gross = PerpsMath.unrealizedPnl(side: side, entryPrice: entry, markPrice: fillPrice, size: size)
        let rate = PerpsMath.baseTakerFeeRate + (kind == .liquidated ? 0 : PerpsConfig.builderFeeRate)
        let fees = (size * fillPrice * rate).rounded(scale: 2)
        let margin = PerpsMarginFlows.margin(of: position)
        return PerpsOutcome(kind: kind, coin: position.coin, isLong: position.isLong, leverage: position.leverage.value,
                            triggerPrice: triggerPrice, fillPrice: fillPrice, size: size, fees: fees,
                            netPnl: (gross - fees).rounded(scale: 2), margin: margin)
    }

    /// From the closing fills the venue reports: P&L is `closedPnl` minus
    /// fees, the price is size-weighted.
    static func fromFills(_ fills: [HLFill], kind: Kind, isLong: Bool, leverage: Int, margin: Decimal, triggerPrice: Decimal?) -> PerpsOutcome? {
        guard let coin = fills.first?.coin else { return nil }
        let size = fills.reduce(Decimal(0)) { $0 + $1.sz.value }
        guard size > 0 else { return nil }
        let price = fills.reduce(Decimal(0)) { $0 + $1.px.value * $1.sz.value } / size
        let fees = fills.reduce(Decimal(0)) { $0 + $1.fee.value }
        let closed = fills.reduce(Decimal(0)) { $0 + $1.closedPnl.value }
        return PerpsOutcome(kind: kind, coin: coin, isLong: isLong, leverage: leverage, triggerPrice: triggerPrice, fillPrice: price,
                            size: size, fees: fees, netPnl: closed - fees, margin: margin)
    }
}
