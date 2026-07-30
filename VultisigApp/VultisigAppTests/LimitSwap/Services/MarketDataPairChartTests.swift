//
//  MarketDataPairChartTests.swift
//  VultisigAppTests
//
//  `pairChart` — the two-leg composition, what it forwards, and every way it
//  degrades to no chart rather than to a wrong one.
//

@testable import VultisigApp
import Foundation
import XCTest

final class MarketDataPairChartTests: XCTestCase {

    // MARK: - Fixtures

    private static let bitcoin = CoinMeta(
        chain: .bitcoin,
        ticker: "BTC",
        logo: "btc",
        decimals: 8,
        priceProviderId: "bitcoin",
        contractAddress: "",
        isNativeToken: true
    )

    private static let ethereum = CoinMeta(
        chain: .ethereum,
        ticker: "ETH",
        logo: "eth",
        decimals: 18,
        priceProviderId: "ethereum",
        contractAddress: "",
        isNativeToken: true
    )

    private static func flatSeries(price: Double, count: Int = 40) -> MarketChart {
        MarketChart(points: (0..<count).map { index in
            MarketChartPoint(date: Date(timeIntervalSince1970: Double(index) * 3600), price: price)
        })
    }

    /// Records what it was asked for and answers from a per-ticker table.
    /// An actor because the protocol is `Sendable` and the two legs are
    /// deliberately fetched concurrently — the recording has to survive that.
    private actor StubMarketDataService: MarketDataServiceProtocol {

        private let series: [String: MarketChart]
        private(set) var requests: [(ticker: String, range: MarketChartRange, currency: SettingsCurrency)] = []

        init(series: [String: MarketChart]) {
            self.series = series
        }

        // Synchronous: an actor-isolated method still witnesses the protocol's
        // `async` requirement, and callers still reach it with `await`.
        func chart(
            for coin: CoinMeta,
            range: MarketChartRange,
            currency: SettingsCurrency
        ) -> MarketChart? {
            requests.append((coin.ticker, range, currency))
            return series[coin.ticker]
        }

        func stats(for _: CoinMeta, currency _: SettingsCurrency) -> CoinMarketStats? {
            nil
        }

        func recordedRequests() -> [(ticker: String, range: MarketChartRange, currency: SettingsCurrency)] {
            requests
        }
    }

    // MARK: - Composition

    func testDividesTheBaseSeriesByTheQuoteSeries() async throws {
        let service = StubMarketDataService(series: [
            "BTC": Self.flatSeries(price: 120_000),
            "ETH": Self.flatSeries(price: 4_000)
        ])

        let result = await service.pairChart(
            base: Self.bitcoin, quote: Self.ethereum, range: .month, currency: .USD
        )
        let chart = try XCTUnwrap(result)

        XCTAssertEqual(chart.points.count, MarketChartRendering.pointCount)
        for point in chart.points {
            XCTAssertEqual(point.price, 30, accuracy: 1e-9)
        }
    }

    func testForwardsTheSameRangeAndCurrencyToBothLegs() async throws {
        // Both legs must read the SAME cache entries the rest of the app
        // populated for this currency — and a ratio built from two different
        // ranges would not be a ratio at all.
        let service = StubMarketDataService(series: [
            "BTC": Self.flatSeries(price: 120_000),
            "ETH": Self.flatSeries(price: 4_000)
        ])

        _ = await service.pairChart(base: Self.bitcoin, quote: Self.ethereum, range: .year, currency: .EUR)
        let requests = await service.recordedRequests()

        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(Set(requests.map(\.ticker)), ["BTC", "ETH"])
        XCTAssertTrue(requests.allSatisfy { $0.range == .year })
        XCTAssertTrue(requests.allSatisfy { $0.currency == .EUR })
    }

    func testRatioIsIndependentOfTheCurrencyItWasFetchedIn() async throws {
        // The fiat unit cancels: the same pair priced in a currency worth half
        // as much per unit yields the same ratio.
        let usd = StubMarketDataService(series: [
            "BTC": Self.flatSeries(price: 120_000),
            "ETH": Self.flatSeries(price: 4_000)
        ])
        let eur = StubMarketDataService(series: [
            "BTC": Self.flatSeries(price: 60_000),
            "ETH": Self.flatSeries(price: 2_000)
        ])

        let usdResult = await usd.pairChart(base: Self.bitcoin, quote: Self.ethereum, range: .month, currency: .USD)
        let eurResult = await eur.pairChart(base: Self.bitcoin, quote: Self.ethereum, range: .month, currency: .EUR)
        let inUsd = try XCTUnwrap(usdResult)
        let inEur = try XCTUnwrap(eurResult)

        XCTAssertEqual(inUsd.points.map(\.price), inEur.points.map(\.price))
    }

    // MARK: - Degradation

    func testReturnsNilWhenTheBaseLegHasNoSource() async {
        let service = StubMarketDataService(series: ["ETH": Self.flatSeries(price: 4_000)])

        let chart = await service.pairChart(base: Self.bitcoin, quote: Self.ethereum, range: .month, currency: .USD)

        XCTAssertNil(chart)
    }

    func testReturnsNilWhenTheQuoteLegHasNoSource() async {
        let service = StubMarketDataService(series: ["BTC": Self.flatSeries(price: 120_000)])

        let chart = await service.pairChart(base: Self.bitcoin, quote: Self.ethereum, range: .month, currency: .USD)

        XCTAssertNil(chart)
    }

    func testReturnsNilWhenTheTwoHistoriesCannotBeReconciled() async {
        // Non-overlapping windows — nothing dishonest can be drawn from them.
        let old = MarketChart(points: (0..<40).map {
            MarketChartPoint(date: Date(timeIntervalSince1970: Double($0) * 60), price: 120_000)
        })
        let recent = MarketChart(points: (0..<40).map {
            MarketChartPoint(date: Date(timeIntervalSince1970: 1_000_000 + Double($0) * 60), price: 4_000)
        })
        let service = StubMarketDataService(series: ["BTC": old, "ETH": recent])

        let chart = await service.pairChart(base: Self.bitcoin, quote: Self.ethereum, range: .month, currency: .USD)

        XCTAssertNil(chart)
    }
}
