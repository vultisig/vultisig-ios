//
//  PerpsViewModels.swift
//  VultisigApp
//
//  Perps view models. Read-only: they fetch Hyperliquid /info data and
//  plan orders, and stop at the review. No signature is requested.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "perps")

enum PerpsFormat {
    private static let usd: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()

    static func usd(_ value: Decimal, signed: Bool = false) -> String {
        // Below half a cent is zero: never "-$0.00".
        let value = value.rounded(scale: 2)
        let text = usd.string(from: NSDecimalNumber(decimal: value < 0 ? -value : value)) ?? "-"
        // Typographic minus (U+2212), the same width as "+".
        if value < 0 { return "\u{2212}" + text }
        return signed && value > 0 ? "+" + text : text
    }

    /// Prices keep the venue's precision: 5 significant figures.
    static func price(_ value: Decimal) -> String { "$" + plainPrice(value) }

    /// "$100" for whole amounts, "$100.50" otherwise.
    static func amount(_ value: Decimal) -> String {
        value == value.rounded(scale: 0) ? "$" + plainPrice(value.rounded(scale: 0)).replacingOccurrences(of: ".00", with: "") : usd(value)
    }

    /// "0x3868…3533"
    static func shortAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }

    /// Display precision for a price: whole dollars from $1,000, cents from $1,
    /// five significant figures below that. "66,468", "91.49", "0.52341".
    static func priceDecimals(_ value: Decimal) -> Int? {
        let magnitude = value < 0 ? -value : value
        if magnitude >= 1000 { return 0 }
        if magnitude >= 1 { return 2 }
        return nil
    }

    static func plainPrice(_ value: Decimal, grouped: Bool = true) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.usesGroupingSeparator = grouped
        if let decimals = priceDecimals(value) {
            formatter.minimumFractionDigits = decimals
            formatter.maximumFractionDigits = decimals
        } else {
            formatter.usesSignificantDigits = true
            formatter.maximumSignificantDigits = 5
        }
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "-"
    }

    /// A price rounded to what the UI shows, so the trigger sent is the one displayed.
    static func roundedPrice(_ value: Decimal) -> Decimal {
        guard let decimals = priceDecimals(value) else { return value }
        return value.rounded(scale: decimals)
    }

    /// Dot decimals like every other perps number (prices and dollars are en_US).
    static func percent(_ value: Decimal, digits: Int = 2, signed: Bool = true) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        let text = String(format: "%.\(digits)f%%", locale: Locale(identifier: "en_US_POSIX"), number)
        if number < 0 { return "\u{2212}" + text.dropFirst() }
        return signed ? "+" + text : text
    }

    static func compactUsd(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        switch number {
        case 1_000_000_000...: return String(format: "$%.1fB", number / 1_000_000_000)
        case 1_000_000...: return String(format: "$%.1fM", number / 1_000_000)
        case 1_000...: return String(format: "$%.1fK", number / 1_000)
        default: return usd(value)
        }
    }
}

/// Chart windows on the market and position screens.
enum PerpsTimeframe: String, CaseIterable, Hashable {
    case hour = "1H"
    case day = "1D"
    case week = "1W"
    case month = "1M"
    case all = "ALL"

    var window: (interval: HLCandleInterval, lookback: TimeInterval) {
        let day: TimeInterval = 86_400
        switch self {
        case .hour: return (.oneMinute, 3_600)
        case .day: return (.fifteenMinutes, day)
        case .week: return (.oneHour, 7 * day)
        case .month: return (.fourHours, 30 * day)
        case .all: return (.oneDay, 3 * 365 * day)
        }
    }
}

@MainActor
final class PerpsHubViewModel: ObservableObject {
    @Published private(set) var markets: [PerpsMarket] = []
    @Published private(set) var account: PerpsAccountSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository: PerpsRepository

    init(repository: PerpsRepository = PerpsRepositories.make()) {
        self.repository = repository
    }

    /// The three busiest markets by 24h volume; "See all" opens search.
    var exploreMarkets: [PerpsMarket] {
        Array(markets.sorted { $0.dayVolume > $1.dayVolume }.prefix(3))
    }

    /// No money and nothing open: the first-visit intro.
    var isFirstVisit: Bool { account.map { $0.isEmpty } ?? true }

    func load(vault: Vault) async {
        // The VULT tier sets the builder fee; resolved beside the account, off the critical path.
        Task { await PerpsVultTier.refresh(vault: vault) }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let marketList = repository.markets()
            if let address = PerpsConfig.tradingAccountAddress(vault: vault) {
                account = try await repository.account(address: address)
            }
            markets = try await marketList
        } catch {
            logger.error("Perps hub load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "perpsLoadFailed".localized
        }
    }
}

/// Whether the venue is reachable, and how old the last prices are. A ticket
/// keeps its draft while offline and only re-enables Review after a reconnect
/// has refreshed the price and the account.
@MainActor
final class PerpsConnection: ObservableObject {
    @Published fileprivate(set) var isOffline = false
    @Published fileprivate(set) var pricesAsOf: Date?
    @Published fileprivate(set) var market: PerpsMarket?
    @Published fileprivate(set) var account: PerpsAccountSnapshot?
    fileprivate var onReconnect: (() async -> Void)?

    /// Minutes since the last good prices, at least 1.
    func minutesStale(now: Date = Date()) -> Int {
        guard let pricesAsOf else { return 1 }
        return max(1, Int(now.timeIntervalSince(pricesAsOf) / 60))
    }

    func reconnect() async { await onReconnect?() }
}

@MainActor
final class PerpsMarketViewModel: ObservableObject {
    @Published private(set) var market: PerpsMarket?
    @Published private(set) var points: [MarketChartPoint] = []
    @Published private(set) var account: PerpsAccountSnapshot?
    @Published private(set) var isLoadingChart = false
    @Published private(set) var timeframe: PerpsTimeframe = .day

    let coin: String
    let connection = PerpsConnection()
    private let repository: PerpsRepository
    private var address: String?

    init(coin: String, repository: PerpsRepository = PerpsRepositories.make()) {
        self.coin = coin
        self.repository = repository
        connection.onReconnect = { [weak self] in await self?.reconnect() }
    }

    var position: HLPosition? { account?.position(coin: coin) }
    var triggers: [HLFrontendOrder] { account?.triggers(coin: coin) ?? [] }

    /// 24h move in dollars and percent, from the previous day's price.
    var dayChange: (amount: Decimal, percent: Decimal)? {
        guard let market else { return nil }
        return (market.markPrice - market.previousDayPrice, market.change24h)
    }

    func load(vault: Vault) async {
        address = PerpsConfig.tradingAccountAddress(vault: vault)
        Task { await PerpsVultTier.refresh(vault: vault) }
        await refreshPrices()
        #if DEBUG
        // Debug only: the venue unreachable, prices two minutes old.
        if PerpsDemoState.current.contains(.offline) {
            connection.isOffline = true
            connection.pricesAsOf = Date().addingTimeInterval(-120)
        }
        #endif
        await loadChart()
    }

    /// Market and account in one go; any failure marks the connection offline
    /// and keeps the last good values.
    func refreshPrices() async {
        #if DEBUG
        if PerpsDemoState.current.contains(.offline), market != nil { return }
        #endif
        do {
            let fresh = try await repository.markets().first { $0.coin == coin }
            var freshAccount = account
            if let address { freshAccount = try await repository.account(address: address) }
            market = fresh
            account = freshAccount
            connection.market = fresh
            connection.account = freshAccount
            connection.pricesAsOf = Date()
            connection.isOffline = false
        } catch {
            logger.error("Perps market load failed: \(error.localizedDescription, privacy: .public)")
            connection.isOffline = true
        }
    }

    /// A retry after a failed load also fetches the chart the failure skipped.
    private func reconnect() async {
        await refreshPrices()
        if market != nil, points.isEmpty { await loadChart() }
    }

    /// Keeps marks, the account and the open ticket fresh while the screen is up.
    static let pollInterval: Duration = .seconds(15)

    func pollPrices() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.pollInterval)
            guard !Task.isCancelled else { return }
            await refreshPrices()
        }
    }

    func select(_ timeframe: PerpsTimeframe) {
        self.timeframe = timeframe
        Task { await loadChart() }
    }

    func loadChart() async {
        isLoadingChart = true
        defer { isLoadingChart = false }
        let requested = timeframe
        let window = requested.window
        let now = Date()
        do {
            let candles = try await repository.candles(coin: coin, interval: window.interval, since: now.addingTimeInterval(-window.lookback), until: now)
            // A slow load for a timeframe the user already left never overwrites the newer one.
            guard requested == timeframe else { return }
            points = candles.map { MarketChartPoint(date: $0.openTime, price: NSDecimalNumber(decimal: $0.close.value).doubleValue) }
        } catch {
            logger.error("Perps candles failed: \(error.localizedDescription, privacy: .public)")
            guard requested == timeframe else { return }
            points = []
        }
    }
}
