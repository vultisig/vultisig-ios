//
//  PerpsDemoRepository.swift
//  VultisigApp
//
//  Debug only (`-perpsDemoAccount YES`): live markets and candles, with a
//  FICTIONAL funded account so a demo can tell one coherent story ($250
//  added, a $100 2× BTC long with a stop). `-perpsDemoState noPositions`
//  shows the same account before its first trade, `nearLiquidation` swaps the
//  BTC long for a 20× ETH long close to liquidation. No real account is shown
//  and nothing is signed. Release builds never construct it.
//

import Foundation

enum PerpsRepositories {
    static func make() -> PerpsRepository {
        #if DEBUG
        if PerpsConfig.usesDemoAccount { return PerpsDemoRepository() }
        #endif
        return HyperliquidPerpsRepository()
    }
}

#if DEBUG
enum PerpsDemoState: String {
    case addingFunds, tradeOpened, positionClosed, stopNotPlaced, noPositions, nearLiquidation
    case withdraw, withdrawing, withdrawn, modify, addMargin, closeHalf, stopLossHit, takeProfitHit, liquidated, orderFailed
    case account, withdrawSlow, removeMarginBlocked, closeQuarter, closing, partlyClosed, offline
    /// One continuous demo whose account moves on after each review (see `PerpsDemoStory`).
    case story

    /// From `-perpsDemoState <value>[,<value>]`.
    static var current: Set<PerpsDemoState> {
        let raw = UserDefaults.standard.string(forKey: "perpsDemoState") ?? ""
        return Set(raw.split(separator: ",").compactMap { PerpsDemoState(rawValue: String($0)) })
    }
}

final class PerpsDemoRepository: PerpsRepository {
    private let live = HyperliquidPerpsRepository()

    /// BTC and ETH marks are frozen the first time the demo sees them (kept in
    /// UserDefaults), so every launch, every sheet and its review compute from
    /// the same price and the screenshots of one flow agree with each other.
    /// `-perpsDemoFreshPrices YES` takes new ones.
    static let frozenCoins: Set<String> = ["BTC", "ETH"]

    func markets() async throws -> [PerpsMarket] {
        try await live.markets().map(Self.frozen)
    }

    static func frozen(_ market: PerpsMarket) -> PerpsMarket {
        guard frozenCoins.contains(market.coin) else { return market }
        let key = "perpsDemoMark-\(market.coin)"
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: key).flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
        let mark: Decimal
        if let pinned = PerpsDemoStory.pinnedMark(market.coin) {
            // `-perpsDemoMarkBTC 66975`: a given price, e.g. the board's fixture.
            mark = pinned
        } else if let stored, !defaults.bool(forKey: "perpsDemoFreshPrices") {
            mark = stored
        } else {
            mark = PerpsFormat.roundedPrice(market.markPrice)
            defaults.set(NSDecimalNumber(decimal: mark).stringValue, forKey: key)
        }
        // Candles keep the live wiggles, scaled once per launch so they do not drift.
        let scale = PerpsDemoStory.candleScale(for: market.coin) ?? (market.markPrice > 0 ? mark / market.markPrice : 1)
        PerpsDemoStory.setCandleScale(scale, for: market.coin)
        // The day change is fixed (the board's), not the live one: a live -6% day
        // drew a falling chart under a +12% position. The chart is bent to match it.
        let previousDay = (mark / (1 + PerpsDemoStory.dayChange(market.coin, mark: mark))).rounded(scale: 1)
        PerpsDemoStory.setChartEnds(mark: mark, previousDay: previousDay, for: market.coin)
        var copy = PerpsMarket(assetIndex: market.assetIndex, coin: market.coin, szDecimals: market.szDecimals, maxLeverage: market.maxLeverage,
                               onlyIsolated: market.onlyIsolated, markPrice: mark, midPrice: mark, previousDayPrice: previousDay,
                               hourlyFunding: market.hourlyFunding, openInterest: market.openInterest, dayVolume: market.dayVolume)
        copy.marginTiers = market.marginTiers
        return copy
    }

    func candles(coin: String, interval: HLCandleInterval, since: Date, until: Date) async throws -> [HLCandle] {
        let candles = try await live.candles(coin: coin, interval: interval, since: since, until: until)
        guard let scale = PerpsDemoStory.candleScale(for: coin) else { return candles }
        let scaled = candles.map {
            HLCandle(openTimeMs: $0.openTimeMs, open: HLDecimal($0.open.value * scale), close: HLDecimal($0.close.value * scale),
                     high: HLDecimal($0.high.value * scale), low: HLDecimal($0.low.value * scale), volume: $0.volume)
        }
        guard let ends = PerpsDemoStory.chartEnds(for: coin) else { return scaled }
        return Self.bent(scaled, mark: ends.mark, previousDay: ends.previousDay, lookback: until.timeIntervalSince(since))
    }

    /// The candles re-drawn so the line ends on the frozen mark and, over a day
    /// or less, starts where the day change says (the 1D chart opens on the
    /// previous day's price). The live wiggles ride on that straight trend,
    /// damped to at most 35% of the move so the trend reads at a glance.
    /// Longer windows keep their live start and full wiggles.
    static func bent(_ candles: [HLCandle], mark: Decimal, previousDay: Decimal, lookback: TimeInterval) -> [HLCandle] {
        guard let first = candles.first, let last = candles.last, candles.count > 1 else { return candles }
        let day: TimeInterval = 86_400
        let isShort = lookback <= day + 1
        let start = isShort ? mark - (mark - previousDay) * Decimal(lookback / day) : first.close.value
        let oldStart = first.close.value
        let oldEnd = last.close.value
        let span = Decimal(max(1, last.openTimeMs - first.openTimeMs))
        func progress(_ candle: HLCandle) -> Decimal { Decimal(candle.openTimeMs - first.openTimeMs) / span }
        let residuals = candles.map { $0.close.value - (oldStart + (oldEnd - oldStart) * progress($0)) }
        let widest = residuals.map { abs($0) }.max() ?? 0
        let move = abs(mark - start)
        let damping: Decimal = !isShort || widest == 0 ? 1 : min(1, move * (Decimal(string: "0.35") ?? 0) / widest)
        return candles.map { candle in
            let u = progress(candle)
            let oldTrend = oldStart + (oldEnd - oldStart) * u
            let newTrend = start + (mark - start) * u
            func map(_ value: Decimal) -> HLDecimal { HLDecimal(newTrend + (value - oldTrend) * damping) }
            return HLCandle(openTimeMs: candle.openTimeMs, open: map(candle.open.value), close: map(candle.close.value),
                            high: map(candle.high.value), low: map(candle.low.value), volume: candle.volume)
        }
    }

    func account(address: String) async throws -> PerpsAccountSnapshot {
        let markets = try await self.markets()
        let state = PerpsDemoState.current
        let mark = markets.first { $0.coin == "BTC" }?.markPrice ?? 70_000
        if PerpsDemoStory.isOn {
            // Opened at the mark the ticket showed, unless an entry is pinned.
            let entry = PerpsDemoStory.pinnedEntry ?? mark
            switch PerpsDemoStory.stage {
            case .empty: return Self.empty(address: address)
            case .funded: return Self.unfunded(address: address)
            case .opened: return Self.snapshot(address: address, btcMark: mark, entry: entry, now: Date())
            case .withdrawn: return Self.afterWithdrawal(Self.snapshot(address: address, btcMark: mark, entry: entry, now: Date()))
            }
        }
        if state.contains(.noPositions) { return Self.unfunded(address: address) }
        if !state.isDisjoint(with: [.nearLiquidation, .liquidated]), let eth = markets.first(where: { $0.coin == "ETH" }) {
            return Self.nearLiquidation(address: address, ethMark: eth.markPrice)
        }
        // Opened 6% under the mark: the demo reads as a +12% gain, as on the design board.
        let entry = PerpsDemoStory.pinnedEntry ?? (mark * (Decimal(string: "0.94") ?? 1)).rounded(scale: 0)
        var snapshot = Self.snapshot(address: address, btcMark: mark, entry: entry, now: Date())
        if !state.isDisjoint(with: [.withdrawing, .withdrawn, .withdrawSlow]) { snapshot = Self.afterWithdrawal(snapshot) }
        return snapshot
    }

    // swiftlint:disable:next async_without_await
    func activity(address _: String, fills _: [HLFill]) async throws -> [PerpsActivityItem] {
        let now = Date()
        return [
            PerpsActivityItem(id: "demo-open", kind: .trade, coin: "BTC",
                              title: String(format: "perpsActivityOpened".localized, "BTC", "perpsLong".localized),
                              date: now.addingTimeInterval(-120), amount: 200, isSigned: false),
            PerpsActivityItem(id: "demo-add", kind: .transfer, coin: "USDC", title: "perpsActivityAdded".localized,
                              date: now.addingTimeInterval(-900), amount: 250, isSigned: true),
            PerpsActivityItem(id: "demo-close", kind: .trade, coin: "SOL",
                              title: String(format: "perpsActivityClosed".localized, "SOL", "perpsLong".localized),
                              date: now.addingTimeInterval(-86_400 - 3_600), amount: Decimal(string: "44.40") ?? 0, isSigned: true),
            PerpsActivityItem(id: "demo-funding", kind: .funding, coin: "USDC", title: "perpsActivityFunding".localized,
                              date: now.addingTimeInterval(-86_400 - 7_200), amount: Decimal(string: "-0.21") ?? 0, isSigned: true)
        ]
    }

    /// What was added to the trading account.
    static let deposited: Decimal = 250
    /// The withdrawal and the margin top-up the demo shows.
    static let demoWithdrawal: Decimal = 100
    static let demoMarginAdd: Decimal = 50
    /// More than can leave the position, so Review stays disabled.
    static let demoMarginRemove: Decimal = 20

    /// The same account after `demoWithdrawal` left it.
    static func afterWithdrawal(_ snapshot: PerpsAccountSnapshot) -> PerpsAccountSnapshot {
        var after = PerpsAccountSnapshot(
            address: snapshot.address, accountValue: snapshot.accountValue - demoWithdrawal,
            withdrawable: snapshot.withdrawable - demoWithdrawal, marginUsed: snapshot.marginUsed, totalNotional: snapshot.totalNotional,
            positions: snapshot.positions, openOrders: snapshot.openOrders, fills: snapshot.fills
        )
        after.triggerOrders = snapshot.triggerOrders
        after.marginSummaryCrossValue = snapshot.marginSummaryCrossValue - demoWithdrawal
        after.hasWithdrawnBefore = true
        return after
    }

    /// Outcomes for the demo position. A stop fills a little under its
    /// trigger, a take profit a little under its own (6% over entry when none
    /// is set), a liquidation at the liquidation price. Live, these come from
    /// `userFills` through `PerpsOutcome.fromFills`.
    static func outcome(_ kind: PerpsOutcome.Kind, position: HLPosition, triggers: [HLFrontendOrder], market: PerpsMarket) -> PerpsOutcome {
        let entry = position.entryPx?.value ?? market.markPrice
        let sign: Decimal = position.isLong ? 1 : -1
        switch kind {
        case .stopLoss:
            let trigger = triggers.first(where: \.isStopLoss)?.triggerPx?.value
                ?? PerpsFormat.roundedPrice(entry * (1 - sign * PerpsConfig.defaultStopDistance))
            let fill = PerpsFormat.roundedPrice(trigger * (1 - sign * (Decimal(string: "0.0003") ?? 0)))
            return .make(kind: .stopLoss, position: position, fillPrice: fill, triggerPrice: trigger)
        case .takeProfit:
            let trigger = triggers.first(where: \.isTakeProfit)?.triggerPx?.value
                ?? (entry * (1 + sign * (Decimal(string: "0.06") ?? 0)) / 100).rounded(scale: 0) * 100
            let fill = PerpsFormat.roundedPrice(trigger * (1 - sign * (Decimal(string: "0.00016") ?? 0)))
            return .make(kind: .takeProfit, position: position, fillPrice: fill, triggerPrice: trigger)
        case .liquidated:
            let fill = PerpsFormat.roundedPrice(position.liquidationPx?.value ?? market.markPrice)
            return .make(kind: .liquidated, position: position, fillPrice: fill, triggerPrice: nil)
        }
    }

    /// Never funded: the first-visit hub.
    static func empty(address: String) -> PerpsAccountSnapshot {
        PerpsAccountSnapshot(address: address, accountValue: 0, withdrawable: 0, marginUsed: 0,
                             totalNotional: 0, positions: [], openOrders: [], fills: [])
    }

    /// Funded, before the first trade.
    static func unfunded(address: String) -> PerpsAccountSnapshot {
        var snapshot = PerpsAccountSnapshot(address: address, accountValue: deposited, withdrawable: deposited, marginUsed: 0,
                                            totalNotional: 0, positions: [], openOrders: [], fills: [])
        snapshot.marginSummaryCrossValue = deposited
        return snapshot
    }

    /// A $100 2× isolated BTC long at `entry`, with the ticket's default stop (7% under).
    /// Size, margin and fee follow the ticket's own maths, so every screen agrees.
    static func snapshot(address: String, btcMark: Decimal, entry: Decimal, now: Date) -> PerpsAccountSnapshot {
        let size = PerpsMath.size(margin: 100, leverage: 2, price: entry, szDecimals: 5)
        let notional = size * entry
        let initialMargin = notional / 2
        let fee = (notional * (PerpsMath.baseTakerFeeRate + PerpsConfig.builderFeeRate)).rounded(scale: 2)
        let pnl = (btcMark - entry) * size
        let liquidation = PerpsMath.liquidationPrice(side: .long, entryPrice: entry, size: size, collateral: initialMargin, maxLeverage: 40)
        let position = HLPosition(
            coin: "BTC", szi: HLDecimal(size), leverage: HLLeverage(type: "isolated", value: 2), entryPx: HLDecimal(entry),
            positionValue: HLDecimal(size * btcMark), unrealizedPnl: HLDecimal(pnl), returnOnEquity: HLDecimal(pnl / initialMargin),
            liquidationPx: liquidation.map(HLDecimal.init), marginUsed: HLDecimal(initialMargin + pnl), maxLeverage: 40,
            cumFunding: HLCumFunding(sinceOpen: HLDecimal(Decimal(string: "0.02") ?? 0))
        )
        let defaultStop = HLWireFormat.price(PerpsFormat.roundedPrice(entry * (1 - PerpsConfig.defaultStopDistance)), szDecimals: 5)
        // `-perpsDemoStopBTC <price>|liquidation` pins the stop, to show every explainer case.
        let stop = PerpsDemoStory.pinnedStop == "liquidation" ? (liquidation ?? defaultStop)
            : (PerpsDemoStory.pinnedStop.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) } ?? defaultStop)
        let stopOrder = HLFrontendOrder(
            coin: "BTC", oid: 1, side: "A", sz: HLDecimal(0), limitPx: HLDecimal(stop), triggerPx: HLDecimal(stop), isTrigger: true,
            isPositionTpsl: true, reduceOnly: true, orderType: "Stop Market", timestamp: Int64(now.timeIntervalSince1970 * 1000)
        )
        let openFill = HLFill(coin: "BTC", px: HLDecimal(entry), sz: HLDecimal(size), side: "B",
                              time: Int64(now.addingTimeInterval(-120).timeIntervalSince1970 * 1000), dir: "Open Long",
                              closedPnl: HLDecimal(0), fee: HLDecimal(fee), tid: 1, oid: 1)
        // Available = what was added, minus the fee and the margin the long reserves.
        let accountValue = deposited - fee + pnl
        var snapshot = PerpsAccountSnapshot(
            address: address, accountValue: accountValue, withdrawable: deposited - fee - initialMargin,
            marginUsed: initialMargin + pnl, totalNotional: size * btcMark, positions: [position], openOrders: [], fills: [openFill]
        )
        snapshot.triggerOrders = [stopOrder]
        snapshot.marginSummaryCrossValue = accountValue
        snapshot.hasWithdrawnBefore = false
        return snapshot
    }

    /// A 20× isolated ETH long opened 2.31% above the mark: 0.8% from liquidation, so the
    /// warning shows. No stop loss.
    static func nearLiquidation(address: String, ethMark: Decimal) -> PerpsAccountSnapshot {
        let entry = (ethMark * (Decimal(string: "1.0231") ?? 1)).rounded(scale: 0)
        let size = PerpsMath.size(margin: Decimal(string: "131.38") ?? 0, leverage: 20, price: entry, szDecimals: 4)
        let initialMargin = size * entry / 20
        let pnl = (ethMark - entry) * size
        let liquidation = PerpsMath.liquidationPrice(side: .long, entryPrice: entry, size: size, collateral: initialMargin, maxLeverage: 25)
        let position = HLPosition(
            coin: "ETH", szi: HLDecimal(size), leverage: HLLeverage(type: "isolated", value: 20), entryPx: HLDecimal(entry),
            positionValue: HLDecimal(size * ethMark), unrealizedPnl: HLDecimal(pnl), returnOnEquity: HLDecimal(pnl / initialMargin),
            liquidationPx: liquidation.map(HLDecimal.init), marginUsed: HLDecimal(initialMargin + pnl), maxLeverage: 25,
            cumFunding: HLCumFunding(sinceOpen: HLDecimal(Decimal(string: "0.47") ?? 0))
        )
        let accountValue = deposited + pnl
        var snapshot = PerpsAccountSnapshot(
            address: address, accountValue: accountValue, withdrawable: deposited - initialMargin,
            marginUsed: initialMargin + pnl, totalNotional: size * ethMark, positions: [position], openOrders: [], fills: []
        )
        snapshot.marginSummaryCrossValue = accountValue
        return snapshot
    }
}

/// Debug only (`-perpsDemoAccount YES -perpsDemoState story`): one
/// continuous demo. Closing a review stands in for signing it, so the fictional
/// account moves on the way a signed action would (deposit → funded, order →
/// opened, withdraw → withdrawn) and one recording tells the whole story with
/// numbers that agree. `-perpsDemoStoryStart opened` starts later on,
/// `-perpsDemoMarkBTC` / `-perpsDemoEntryBTC` pin the prices. Nothing is signed.
enum PerpsDemoStory {
    enum Stage: String { case empty, funded, opened, withdrawn }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored: Stage?
    /// Set by the withdraw screen; the hub shows "Withdrawing" when it next appears.
    nonisolated(unsafe) private static var withdrawingPending = false

    /// The fictional vault's Arbitrum USDC, enough for the $250 deposit.
    static let vaultUsdc: Decimal = 1_250

    /// What the story deposits: $250 lands after the forwarding and first-deposit fees.
    static var depositPrefill: Decimal { PerpsDemoRepository.deposited + HLCctp.forwardingFee + HLCctp.activationFee }

    static var isOn: Bool { PerpsConfig.usesDemoAccount && PerpsDemoState.current.contains(.story) }

    static var stage: Stage {
        get {
            lock.withLock {
                stored ?? UserDefaults.standard.string(forKey: "perpsDemoStoryStart").flatMap(Stage.init(rawValue:)) ?? .empty
            }
        }
        set { lock.withLock { stored = newValue } }
    }

    nonisolated(unsafe) private static var candleScales: [String: Decimal] = [:]
    nonisolated(unsafe) private static var ends: [String: (mark: Decimal, previousDay: Decimal)] = [:]

    /// The demo's 24h change: the design board's market screen ($66,975, +$737.50, +1.11%) and
    /// ETH list (-0.58%). BTC falls by the same 1.11% when its mark is pinned under
    /// the pinned entry (a stop-loss demo), so a losing position never sits on a
    /// rising line. `-perpsDemoDayChangeBTC 2.5` (percent) overrides it.
    static func dayChange(_ coin: String, mark: Decimal) -> Decimal {
        if let percent = decimal("perpsDemoDayChange\(coin)") { return percent / 100 }
        switch coin {
        case "BTC":
            let change = Decimal(string: "0.011134") ?? 0
            return mark < (pinnedEntry ?? mark) ? -change : change
        case "ETH": return Decimal(string: "-0.0058") ?? 0
        default: return 0
        }
    }

    static func setChartEnds(mark: Decimal, previousDay: Decimal, for coin: String) {
        lock.withLock { ends[coin] = (mark, previousDay) }
    }

    static func chartEnds(for coin: String) -> (mark: Decimal, previousDay: Decimal)? { lock.withLock { ends[coin] } }

    static func setCandleScale(_ scale: Decimal, for coin: String) { lock.withLock { candleScales[coin] = scale } }
    static func candleScale(for coin: String) -> Decimal? { lock.withLock { candleScales[coin] } }

    static func markWithdrawingPending() { lock.withLock { withdrawingPending = true } }

    /// True once after a withdrawal was "sent".
    static func takeWithdrawingPending() -> Bool {
        lock.withLock {
            defer { withdrawingPending = false }
            return withdrawingPending
        }
    }

    static func pinnedMark(_ coin: String) -> Decimal? { decimal("perpsDemoMark\(coin)") }
    static var pinnedEntry: Decimal? { decimal("perpsDemoEntryBTC") }
    static var pinnedStop: String? { PerpsConfig.usesDemoAccount ? UserDefaults.standard.string(forKey: "perpsDemoStopBTC") : nil }

    private static func decimal(_ key: String) -> Decimal? {
        guard PerpsConfig.usesDemoAccount, let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))
    }
}
#endif
