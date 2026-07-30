//
//  LimitChartDisclosureTests.swift
//  VultisigAppTests
//
//  The chart's collapsed-by-default preference, and the rule that a collapsed
//  chart costs no market-data traffic.
//

@testable import VultisigApp
import BigInt
import Foundation
import XCTest

@MainActor
final class LimitChartDisclosureTests: XCTestCase {

    /// Counts what it was asked for, so "collapsed ⇒ no fetch" can be asserted
    /// rather than assumed.
    private actor CountingMarketDataService: MarketDataServiceProtocol {

        private(set) var chartRequests = 0

        func chart(for coin: CoinMeta, range: MarketChartRange, currency: SettingsCurrency) -> MarketChart? {
            chartRequests += 1
            return MarketChart(points: (0..<40).map {
                MarketChartPoint(date: Date(timeIntervalSince1970: Double($0) * 60), price: 100)
            })
        }

        func stats(for _: CoinMeta, currency _: SettingsCurrency) -> CoinMarketStats? { nil }

        func requestCount() -> Int { chartRequests }
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: LimitSwapFormViewModel.chartExpandedKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: LimitSwapFormViewModel.chartExpandedKey)
        super.tearDown()
    }

    private func makeViewModel(service: MarketDataServiceProtocol) -> LimitSwapFormViewModel {
        LimitSwapFormViewModel(
            initialDraft: LimitSwapDraft(
                fromAsset: LimitSwapAsset(
                    chain: .bitcoin, ticker: "BTC", decimals: 8,
                    contractAddress: "", isNativeToken: true, priceProviderId: "bitcoin"
                ),
                toAsset: LimitSwapAsset(
                    chain: .ethereum, ticker: "ETH", decimals: 18,
                    contractAddress: "", isNativeToken: true, priceProviderId: "ethereum"
                )
            ),
            vault: Vault(name: "test"),
            interactor: DefaultLimitSwapInteractor(quoteService: ThorchainService.shared),
            marketDataService: service
        )
    }

    // MARK: - Default

    func testTheChartStartsCollapsed() {
        let vm = makeViewModel(service: CountingMarketDataService())

        XCTAssertFalse(vm.isChartExpanded)
    }

    func testTheChoiceIsRemembered() {
        let first = makeViewModel(service: CountingMarketDataService())
        first.setChartExpanded(true, currency: .USD)

        // A fresh form — a later visit to the screen — reads the stored choice.
        let second = makeViewModel(service: CountingMarketDataService())

        XCTAssertTrue(second.isChartExpanded)
    }

    // MARK: - A collapsed chart costs nothing

    func testCollapsedChartIsNeverFetched() async {
        // The reason the preference is worth having: the fetch is two requests
        // on open and two more on every pair change, and while collapsed nobody
        // is looking at the result.
        let service = CountingMarketDataService()
        let vm = makeViewModel(service: service)

        await vm.refreshPairChart(currency: .USD)

        let count = await service.requestCount()
        XCTAssertEqual(count, 0)
        XCTAssertNil(vm.pairChart)
        XCTAssertFalse(vm.isLoadingPairChart)
    }

    func testExpandingFetchesTheSeries() async throws {
        let service = CountingMarketDataService()
        let vm = makeViewModel(service: service)

        vm.setChartExpanded(true, currency: .USD)
        // The fetch is spawned, so let it land.
        try await Task.sleep(for: .milliseconds(200))

        let count = await service.requestCount()
        XCTAssertEqual(count, 2, "one request per leg")
        XCTAssertNotNil(vm.pairChart)
    }

    func testExpandingRaisesTheLoadingFlagSynchronously() {
        // Otherwise the content renders one frame of "no price history" before
        // the request it is waiting on has even started.
        let vm = makeViewModel(service: CountingMarketDataService())

        vm.setChartExpanded(true, currency: .USD)

        XCTAssertTrue(vm.isLoadingPairChart)
    }

    func testExpandingDoesNotRefetchAnAlreadyLoadedSeries() async throws {
        let service = CountingMarketDataService()
        let vm = makeViewModel(service: service)

        vm.setChartExpanded(true, currency: .USD)
        try await Task.sleep(for: .milliseconds(200))
        let afterFirst = await service.requestCount()

        vm.setChartExpanded(false, currency: .USD)
        vm.setChartExpanded(true, currency: .USD)
        try await Task.sleep(for: .milliseconds(200))

        let afterToggle = await service.requestCount()
        XCTAssertEqual(afterToggle, afterFirst, "collapsing and reopening should not refetch")
    }
}
