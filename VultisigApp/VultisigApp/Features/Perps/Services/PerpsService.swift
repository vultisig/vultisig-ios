//
//  PerpsService.swift
//  VultisigApp
//
//  Repository over the read-only Hyperliquid info client, mapping
//  wire models to the value types the screens use.
//

import Foundation

struct PerpsMarket: Identifiable, Hashable, Sendable {
    let assetIndex: Int
    let coin: String
    let szDecimals: Int
    let maxLeverage: Int
    let onlyIsolated: Bool
    let markPrice: Decimal
    let midPrice: Decimal?
    let previousDayPrice: Decimal
    let hourlyFunding: Decimal
    let openInterest: Decimal
    let dayVolume: Decimal
    var marginTiers: [PerpsMarginTier] = []

    var id: Int { assetIndex }
    var marginSchedule: PerpsMarginSchedule { PerpsMarginSchedule(tiers: marginTiers, fallbackMaxLeverage: maxLeverage) }
    var change24h: Decimal { PerpsMath.percentChange(from: previousDayPrice, to: markPrice) }
    var annualizedFunding: Decimal { PerpsMath.annualizedFunding(hourlyRate: hourlyFunding) }
    var openInterestUsd: Decimal { openInterest * markPrice }
}

/// `userAbstraction`. Unified and portfolio-margin accounts keep their USDC in
/// the spot clearinghouse; their perps state alone is "not meaningful".
enum PerpsAccountMode: Hashable, Sendable {
    case standard(String)
    case unified(String)

    init(raw: String) {
        let lower = raw.lowercased()
        self = lower.contains("unified") || lower.contains("portfolio") ? .unified(raw) : .standard(raw)
    }

    var isUnified: Bool { if case .unified = self { return true } else { return false } }
    var raw: String {
        switch self {
        case .standard(let raw), .unified(let raw): return raw
        }
    }
}

struct PerpsAccountSnapshot: Hashable, Sendable {
    let address: String
    var mode: PerpsAccountMode = .standard("default")
    let accountValue: Decimal
    let withdrawable: Decimal
    let marginUsed: Decimal
    let totalNotional: Decimal
    let positions: [HLPosition]
    let openOrders: [HLOpenOrder]
    let fills: [HLFill]
    var triggerOrders: [HLFrontendOrder] = []
    /// Unified accounts keep their collateral in spot USDC.
    var spotUsdcTotal: Decimal?
    var spotUsdcHold: Decimal = 0
    /// Whether a withdrawal already went out (the one-time activation fee is
    /// then paid). Nil when unknown, which counts as a first withdrawal.
    var hasWithdrawnBefore: Bool?

    private var crossUnrealizedPnl: Decimal {
        positions.filter(\.leverage.isCross).reduce(0) { $0 + $1.unrealizedPnl.value }
    }

    /// Isolated `marginUsed` already includes the position's uPnL.
    private var isolatedMargin: Decimal {
        positions.filter { !$0.leverage.isCross }.reduce(0) { $0 + $1.marginUsed.value }
    }

    /// Collateral behind cross positions, the liquidation formula's equity.
    /// Testnet check (q07): `default` mode = cross account value; `unifiedAccount`
    /// = spot USDC total + cross uPnL - isolated margin.
    var crossCollateral: Decimal {
        guard mode.isUnified, let spotUsdcTotal else { return marginSummaryCrossValue }
        return spotUsdcTotal + crossUnrealizedPnl - isolatedMargin
    }

    var marginSummaryCrossValue: Decimal = 0

    /// What a new order can use. Never equity: open positions reserve margin.
    var availableToTrade: Decimal {
        if mode.isUnified, let spotUsdcTotal { return max(0, spotUsdcTotal - spotUsdcHold) }
        return max(0, accountValue - marginUsed)
    }

    /// Always the server's `withdrawable`, never computed (testnet q06: it is
    /// reduced by open orders and margin in ways a client cannot reproduce).
    var availableToWithdraw: Decimal { withdrawable }

    var equity: Decimal {
        if mode.isUnified, let spotUsdcTotal { return spotUsdcTotal + unrealizedPnl }
        return accountValue
    }

    func position(coin: String) -> HLPosition? { positions.first { $0.coin == coin } }
    func triggers(coin: String) -> [HLFrontendOrder] { triggerOrders.filter { $0.coin == coin && $0.isTrigger == true } }

    var unrealizedPnl: Decimal { positions.reduce(0) { $0 + $1.unrealizedPnl.value } }
    var isEmpty: Bool { accountValue == 0 && positions.isEmpty && openOrders.isEmpty }
}

/// One row in Activity: a trade, a transfer, or a day's funding.
struct PerpsActivityItem: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case trade, transfer, funding }

    let id: String
    let kind: Kind
    let coin: String
    let title: String
    let date: Date
    let amount: Decimal
    /// Shown signed (P&L, transfers in/out, funding) or as a plain value.
    let isSigned: Bool
}

protocol PerpsRepository: Sendable {
    func markets() async throws -> [PerpsMarket]
    func activity(address: String, fills: [HLFill]) async throws -> [PerpsActivityItem]
    func candles(coin: String, interval: HLCandleInterval, since: Date, until: Date) async throws -> [HLCandle]
    func account(address: String) async throws -> PerpsAccountSnapshot
}

final class HyperliquidPerpsRepository: PerpsRepository {
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func markets() async throws -> [PerpsMarket] {
        let response = try await httpClient.request(HyperliquidInfoAPI.metaAndAssetContexts, responseType: HLMetaAndAssetContexts.self)
        return Self.markets(from: response.data)
    }

    func candles(coin: String, interval: HLCandleInterval, since: Date, until: Date) async throws -> [HLCandle] {
        let target = HyperliquidInfoAPI.candleSnapshot(
            coin: coin,
            interval: interval,
            startTimeMs: Int64(since.timeIntervalSince1970 * 1000),
            endTimeMs: Int64(until.timeIntervalSince1970 * 1000)
        )
        return try await httpClient.request(target, responseType: [HLCandle].self).data
    }

    /// Reads the account mode first, then picks the balance source from it.
    func account(address: String) async throws -> PerpsAccountSnapshot {
        let modeRaw = try await httpClient.request(HyperliquidInfoAPI.userAbstraction(user: address), responseType: String.self).data
        let mode = PerpsAccountMode(raw: modeRaw)
        async let state = httpClient.request(HyperliquidInfoAPI.clearinghouseState(user: address), responseType: HLClearinghouseState.self)
        async let orders = httpClient.request(HyperliquidInfoAPI.openOrders(user: address), responseType: [HLOpenOrder].self)
        async let fills = httpClient.request(HyperliquidInfoAPI.userFills(user: address), responseType: [HLFill].self)
        async let triggers = httpClient.request(HyperliquidInfoAPI.frontendOpenOrders(user: address), responseType: [HLFrontendOrder].self)
        var snapshot = try await Self.snapshot(address: address, state: state.data, orders: orders.data, fills: fills.data)
        snapshot.mode = mode
        snapshot.triggerOrders = try await triggers.data
        if mode.isUnified {
            let spot = try await httpClient.request(HyperliquidInfoAPI.spotClearinghouseState(user: address), responseType: HLSpotClearinghouseState.self).data
            let usdc = spot.balances.first { $0.coin == "USDC" }
            snapshot.spotUsdcTotal = usdc?.total.value
            snapshot.spotUsdcHold = usdc?.hold.value ?? 0
        }
        return snapshot
    }

    func activity(address: String, fills: [HLFill]) async throws -> [PerpsActivityItem] {
        let since = Int64(Date().addingTimeInterval(-30 * 86_400).timeIntervalSince1970 * 1000)
        async let ledger = httpClient.request(HyperliquidInfoAPI.ledgerUpdates(user: address, startTimeMs: since), responseType: [HLLedgerUpdate].self)
        async let funding = httpClient.request(HyperliquidInfoAPI.funding(user: address, startTimeMs: since), responseType: [HLFundingPayment].self)
        return try await Self.activity(fills: fills, ledger: ledger.data, funding: funding.data)
    }

    /// Fills grouped by order, ledger transfers as-is, funding summed per day.
    static func activity(fills: [HLFill], ledger: [HLLedgerUpdate], funding: [HLFundingPayment]) -> [PerpsActivityItem] {
        let orders = Dictionary(grouping: fills, by: \.oid).compactMap { oid, parts -> PerpsActivityItem? in
            guard let first = parts.min(by: { $0.time < $1.time }) else { return nil }
            let size = parts.reduce(Decimal(0)) { $0 + $1.sz.value }
            let pnl = parts.reduce(Decimal(0)) { $0 + $1.closedPnl.value }
            let isClose = first.dir.hasPrefix("Close")
            let side = first.dir.lowercased().contains("long") ? "perpsLong".localized : "perpsShort".localized
            let title = String(format: (isClose ? "perpsActivityClosed" : "perpsActivityOpened").localized, first.coin, side)
            return PerpsActivityItem(id: "o\(oid)", kind: .trade, coin: first.coin, title: title,
                                     date: Date(timeIntervalSince1970: TimeInterval(first.time) / 1000),
                                     amount: isClose ? pnl : size * first.px.value, isSigned: isClose)
        }
        let transfers = ledger.compactMap { update -> PerpsActivityItem? in
            guard let usdc = update.delta.usdc?.value else { return nil }
            let isOut = update.delta.type.lowercased().contains("withdraw")
            return PerpsActivityItem(id: "l\(update.hash)\(update.time)", kind: .transfer, coin: "USDC",
                                     title: (isOut ? "perpsActivityWithdrew" : "perpsActivityAdded").localized,
                                     date: Date(timeIntervalSince1970: TimeInterval(update.time) / 1000),
                                     amount: isOut ? -usdc : usdc, isSigned: true)
        }
        let calendar = Calendar.current
        let fundingDays = Dictionary(grouping: funding) { calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.time) / 1000)) }
            .map { day, payments in
                PerpsActivityItem(id: "f\(day.timeIntervalSince1970)", kind: .funding, coin: "USDC", title: "perpsActivityFunding".localized,
                                  date: day, amount: payments.reduce(Decimal(0)) { $0 + $1.delta.usdc.value }, isSigned: true)
            }
        return (orders + transfers + fundingDays).sorted { $0.date > $1.date }
    }

    static func marginTiers(for meta: HLAssetMeta, tables: [HLMarginTableEntry]?) -> [PerpsMarginTier] {
        guard let id = meta.marginTableId else { return [] }
        if id < 50 { return [PerpsMarginTier(lowerBound: 0, maxLeverage: id)] }
        let table = tables?.first { $0.id == id }?.table
        return table?.marginTiers.map { PerpsMarginTier(lowerBound: $0.lowerBound.value, maxLeverage: $0.maxLeverage) } ?? []
    }

    static func markets(from response: HLMetaAndAssetContexts) -> [PerpsMarket] {
        zip(response.meta.universe.indices, zip(response.meta.universe, response.contexts)).compactMap { index, pair in
            let (meta, context) = pair
            // Skip delisted assets and metadata the math cannot use safely
            // (leverage ranges, maintenance = 1 / (2 * maxLeverage), lot sizes).
            guard meta.isDelisted != true, meta.maxLeverage >= 1, (0...6).contains(meta.szDecimals),
                  context.markPx.value > 0 else { return nil }
            return PerpsMarket(
                assetIndex: index,
                coin: meta.name,
                szDecimals: meta.szDecimals,
                maxLeverage: meta.maxLeverage,
                onlyIsolated: meta.onlyIsolated ?? false,
                markPrice: context.markPx.value,
                midPrice: context.midPx?.value,
                previousDayPrice: context.prevDayPx.value,
                hourlyFunding: context.funding.value,
                openInterest: context.openInterest.value,
                dayVolume: context.dayNtlVlm.value,
                marginTiers: marginTiers(for: meta, tables: response.meta.marginTables)
            )
        }
    }

    static func snapshot(address: String, state: HLClearinghouseState, orders: [HLOpenOrder], fills: [HLFill]) -> PerpsAccountSnapshot {
        var snapshot = PerpsAccountSnapshot(
            address: address,
            accountValue: state.marginSummary.accountValue.value,
            withdrawable: state.withdrawable.value,
            marginUsed: state.marginSummary.totalMarginUsed.value,
            totalNotional: state.marginSummary.totalNtlPos.value,
            positions: state.assetPositions.map(\.position),
            openOrders: orders,
            fills: Array(fills.prefix(300))
        )
        snapshot.marginSummaryCrossValue = state.crossMarginSummary.accountValue.value
        return snapshot
    }
}
