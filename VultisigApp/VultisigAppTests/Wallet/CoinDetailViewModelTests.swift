//
//  CoinDetailViewModelTests.swift
//  VultisigAppTests
//
//  Chart/stats state on the coin-detail screen: the range switch keeping the
//  previous series on screen instead of collapsing to a spinner, the
//  unsupported-token path, and which number drives the change chip.
//

@testable import VultisigApp
import Foundation
import XCTest

@MainActor
final class CoinDetailViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private static func coin(
        chain: Chain = .bitcoin,
        ticker: String = "BTC",
        priceProviderId: String = "bitcoin",
        contractAddress: String = "",
        isNativeToken: Bool = true
    ) -> Coin {
        let meta = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: ticker.lowercased(),
            decimals: 8,
            priceProviderId: priceProviderId,
            contractAddress: contractAddress,
            isNativeToken: isNativeToken
        )
        return Coin(asset: meta, address: "test-address", hexPublicKey: "")
    }

    /// Solana SPL token with no price-provider id: pool-priced, and Solana has
    /// no CoinGecko asset platform, so there is no market-data source.
    private static func poolPricedCoin() -> Coin {
        coin(
            chain: .solana,
            ticker: "POOL",
            priceProviderId: "",
            contractAddress: "So11111111111111111111111111111111111111112",
            isNativeToken: false
        )
    }

    private static func chart(from opening: Double, to closing: Double) -> MarketChart {
        MarketChart(points: (0..<20).map { index in
            let progress = Double(index) / 19
            return MarketChartPoint(
                date: Date(timeIntervalSince1970: TimeInterval(index) * 300),
                price: opening + (closing - opening) * progress
            )
        })
    }

    // MARK: - Support

    func testSupportedCoinResolvesAMarketDataSource() {
        let viewModel = CoinDetailViewModel(coin: Self.coin(), marketDataService: GatedMarketDataService())
        XCTAssertTrue(viewModel.supportsMarketData)
    }

    func testPoolPricedCoinHasNoMarketDataSource() {
        let viewModel = CoinDetailViewModel(
            coin: Self.poolPricedCoin(),
            marketDataService: GatedMarketDataService()
        )
        XCTAssertFalse(viewModel.supportsMarketData)
        XCTAssertFalse(viewModel.showsChartSection)
    }

    func testPoolPricedCoinNeverAsksTheService() async throws {
        let service = GatedMarketDataService()
        let viewModel = CoinDetailViewModel(coin: Self.poolPricedCoin(), marketDataService: service)

        viewModel.loadMarketDataIfNeeded()
        try await Task.sleep(nanoseconds: 20_000_000)

        let requested = await service.requestedRanges
        XCTAssertTrue(requested.isEmpty)
        XCTAssertNil(viewModel.chart)
    }

    // MARK: - Loading

    func testFirstLoadPopulatesTheChart() async throws {
        let service = GatedMarketDataService()
        await service.setChart(Self.chart(from: 100, to: 110), for: .day)
        let viewModel = CoinDetailViewModel(coin: Self.coin(), marketDataService: service)

        viewModel.loadMarketDataIfNeeded()
        XCTAssertTrue(viewModel.isLoadingChart)
        XCTAssertTrue(viewModel.showsChartSection, "the placeholder must hold the space while loading")

        await service.release(.day)
        try await waitUntil { viewModel.chart != nil }

        XCTAssertFalse(viewModel.isLoadingChart)
        XCTAssertTrue(viewModel.hasAttemptedChartLoad)
    }

    func testSectionIsDroppedWhenNoSeriesResolves() async throws {
        let service = GatedMarketDataService()
        await service.setChart(nil, for: .day)
        let viewModel = CoinDetailViewModel(coin: Self.coin(), marketDataService: service)

        viewModel.loadMarketDataIfNeeded()
        await service.release(.day)
        try await waitUntil { viewModel.hasAttemptedChartLoad }

        XCTAssertNil(viewModel.chart)
        XCTAssertFalse(viewModel.showsChartSection)
    }

    func testSecondLoadInTheSameCurrencyIsANoOp() async throws {
        let service = GatedMarketDataService()
        await service.setChart(Self.chart(from: 100, to: 110), for: .day)
        let viewModel = CoinDetailViewModel(coin: Self.coin(), marketDataService: service)

        viewModel.loadMarketDataIfNeeded()
        await service.release(.day)
        try await waitUntil { viewModel.chart != nil }

        viewModel.loadMarketDataIfNeeded()
        try await Task.sleep(nanoseconds: 20_000_000)

        let requested = await service.requestedRanges
        XCTAssertEqual(requested, [.day])
    }

    // MARK: - Range switching

    func testRangeSwitchKeepsThePreviousSeriesOnScreen() async throws {
        let service = GatedMarketDataService()
        let dayChart = Self.chart(from: 100, to: 110)
        let weekChart = Self.chart(from: 100, to: 90)
        await service.setChart(dayChart, for: .day)
        await service.setChart(weekChart, for: .week)

        let viewModel = CoinDetailViewModel(coin: Self.coin(), marketDataService: service)
        viewModel.loadMarketDataIfNeeded()
        await service.release(.day)
        try await waitUntil { viewModel.chart != nil }

        viewModel.selectRange(.week)

        // The whole point: the layout must not collapse while the next series
        // loads. The old one stays, flagged as loading so the view can dim it.
        XCTAssertEqual(viewModel.chart, dayChart)
        XCTAssertTrue(viewModel.isLoadingChart)
        XCTAssertTrue(viewModel.showsChartSection)

        await service.release(.week)
        try await waitUntil { viewModel.chart == weekChart }
        XCTAssertFalse(viewModel.isLoadingChart)
    }

    func testSelectingTheCurrentRangeDoesNotRefetch() async throws {
        let service = GatedMarketDataService()
        await service.setChart(Self.chart(from: 100, to: 110), for: .day)
        let viewModel = CoinDetailViewModel(coin: Self.coin(), marketDataService: service)

        viewModel.loadMarketDataIfNeeded()
        await service.release(.day)
        try await waitUntil { viewModel.chart != nil }

        viewModel.selectRange(.day)
        try await Task.sleep(nanoseconds: 20_000_000)

        let requested = await service.requestedRanges
        XCTAssertEqual(requested, [.day])
    }

    func testAbandonedRangeResponseDoesNotOverwriteTheSelectedOne() async throws {
        let service = GatedMarketDataService()
        let dayChart = Self.chart(from: 100, to: 110)
        let weekChart = Self.chart(from: 100, to: 90)
        await service.setChart(dayChart, for: .day)
        await service.setChart(weekChart, for: .week)

        let viewModel = CoinDetailViewModel(coin: Self.coin(), marketDataService: service)
        viewModel.loadMarketDataIfNeeded()

        // Switch away before the first range ever answers, then let the stale
        // one through after the new one has landed.
        viewModel.selectRange(.week)
        await service.release(.week)
        try await waitUntil { viewModel.chart == weekChart }

        await service.release(.day)
        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(viewModel.chart, weekChart)
        XCTAssertEqual(viewModel.selectedRange, .week)
    }

    // MARK: - Change

    func testChangeSignFollowsTheChartEndpoints() async throws {
        let service = GatedMarketDataService()
        await service.setChart(Self.chart(from: 100, to: 90), for: .day)
        let viewModel = CoinDetailViewModel(coin: Self.coin(), marketDataService: service)

        viewModel.loadMarketDataIfNeeded()
        await service.release(.day)
        try await waitUntil { viewModel.chart != nil }

        XCTAssertFalse(viewModel.isChangePositive)
        XCTAssertEqual(try XCTUnwrap(viewModel.displayedChangeFraction), -0.1, accuracy: 0.0001)
    }

    func testRisingChartReadsAsPositive() async throws {
        let service = GatedMarketDataService()
        await service.setChart(Self.chart(from: 100, to: 110), for: .day)
        let viewModel = CoinDetailViewModel(coin: Self.coin(), marketDataService: service)

        viewModel.loadMarketDataIfNeeded()
        await service.release(.day)
        try await waitUntil { viewModel.chart != nil }

        XCTAssertTrue(viewModel.isChangePositive)
    }

    func testChangeFallsBackToTheStatsFigureWithoutAChart() async throws {
        let service = GatedMarketDataService()
        await service.setChart(nil, for: .day)
        await service.setStats(try Self.statsWith24hChange(-2.5))
        let viewModel = CoinDetailViewModel(coin: Self.coin(), marketDataService: service)

        viewModel.loadMarketDataIfNeeded()
        await service.release(.day)
        try await waitUntil { viewModel.stats != nil }

        XCTAssertEqual(try XCTUnwrap(viewModel.displayedChangeFraction), -0.025, accuracy: 0.0001)
        XCTAssertFalse(viewModel.isChangePositive)
    }

    // MARK: - Helpers

    private static func statsWith24hChange(_ percentage: Double) throws -> CoinMarketStats {
        let json = Data(#"{"id":"bitcoin","price_change_percentage_24h":\#(percentage)}"#.utf8)
        return try JSONDecoder().decode(CoinMarketStats.self, from: json)
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition", file: file, line: line)
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

// MARK: - Test double

/// A market-data service whose answers are held until the test releases them,
/// so the "previous series stays on screen while the next loads" behaviour can
/// be observed mid-flight instead of inferred from timing.
private actor GatedMarketDataService: MarketDataServiceProtocol {
    private var charts: [MarketChartRange: MarketChart?] = [:]
    private var statsValue: CoinMarketStats?
    private var waiters: [MarketChartRange: CheckedContinuation<Void, Never>] = [:]
    private var released: Set<MarketChartRange> = []
    private(set) var requestedRanges: [MarketChartRange] = []

    func setChart(_ chart: MarketChart?, for range: MarketChartRange) {
        charts[range] = chart
    }

    func setStats(_ stats: CoinMarketStats?) {
        statsValue = stats
    }

    /// Lets the pending (or next) answer for `range` through.
    func release(_ range: MarketChartRange) {
        released.insert(range)
        waiters.removeValue(forKey: range)?.resume()
    }

    func chart(
        for coin: CoinMeta,
        range: MarketChartRange,
        currency: SettingsCurrency
    ) async -> MarketChart? {
        requestedRanges.append(range)

        if !released.contains(range) {
            await withCheckedContinuation { continuation in
                waiters[range] = continuation
            }
        }

        return charts[range] ?? nil
    }

    func stats(for coin: CoinMeta, currency: SettingsCurrency) async -> CoinMarketStats? {
        statsValue
    }
}
