//
//  LimitSwapInteractorTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import XCTest

final class LimitSwapInteractorTests: XCTestCase {

    private var quoteService: MockLimitSwapQuoteService!
    private var interactor: DefaultLimitSwapInteractor!

    override func setUp() async throws {
        try await super.setUp()
        quoteService = MockLimitSwapQuoteService()
        interactor = DefaultLimitSwapInteractor(quoteService: quoteService)
    }

    override func tearDown() async throws {
        interactor = nil
        quoteService = nil
        try await super.tearDown()
    }

    // MARK: - fetchMarketPrice

    func testFetchMarketPriceDelegatesToQuoteService() async throws {
        quoteService.marketPriceResult = .success(Decimal(string: "16.5")!)

        let price = try await interactor.fetchMarketPrice(
            sourceAsset: "BTC.BTC",
            sourceAmount: BigInt(100_000_000),
            sourceDecimals: 8,
            targetAsset: "ETH.ETH",
            targetDecimals: 18,
            destinationAddress: "0xabc"
        )

        XCTAssertEqual(price, Decimal(string: "16.5")!)
        XCTAssertEqual(quoteService.marketPriceCallCount, 1)
    }

    func testFetchMarketPriceErrorPropagates() async {
        struct UpstreamError: Error, Equatable {}
        quoteService.marketPriceResult = .failure(UpstreamError())

        do {
            _ = try await interactor.fetchMarketPrice(
                sourceAsset: "BTC.BTC",
                sourceAmount: BigInt(1),
                sourceDecimals: 8,
                targetAsset: "ETH.ETH",
                targetDecimals: 18,
                destinationAddress: "0xabc"
            )
            XCTFail("Expected throw")
        } catch is UpstreamError {
            // expected
        } catch {
            XCTFail("Expected UpstreamError, got \(error)")
        }
    }
}
