//
//  MockLimitSwapQuoteServiceTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import XCTest

final class MockLimitSwapQuoteServiceTests: XCTestCase {

    // MARK: - market price

    func testMarketPriceReturnsStubbedValue() async throws {
        let mock = MockLimitSwapQuoteService()
        mock.marketPriceResult = .success(Decimal(string: "16.5")!)

        let price = try await mock.fetchCurrentMarketPrice(
            sourceAsset: "BTC.BTC",
            sourceAmount: BigInt(100_000_000),
            sourceDecimals: 8,
            targetAsset: "ETH.ETH",
            targetDecimals: 18,
            destinationAddress: "0xabc"
        )

        XCTAssertEqual(price, Decimal(string: "16.5")!)
        XCTAssertEqual(mock.marketPriceCallCount, 1)
    }

    func testMarketPriceThrowsConfiguredError() async {
        struct CustomError: Error, Equatable {}

        let mock = MockLimitSwapQuoteService()
        mock.marketPriceResult = .failure(CustomError())

        do {
            _ = try await mock.fetchCurrentMarketPrice(
                sourceAsset: "BTC.BTC",
                sourceAmount: BigInt(100_000_000),
                sourceDecimals: 8,
                targetAsset: "ETH.ETH",
                targetDecimals: 18,
                destinationAddress: "0xabc"
            )
            XCTFail("Expected throw")
        } catch let error as CustomError {
            XCTAssertEqual(error, CustomError())
        } catch {
            XCTFail("Expected CustomError, got \(error)")
        }
        XCTAssertEqual(mock.marketPriceCallCount, 1)
    }

    func testMarketPriceUnstubbedThrowsNotStubbed() async {
        let mock = MockLimitSwapQuoteService()

        do {
            _ = try await mock.fetchCurrentMarketPrice(
                sourceAsset: "BTC.BTC",
                sourceAmount: BigInt(1),
                sourceDecimals: 8,
                targetAsset: "ETH.ETH",
                targetDecimals: 18,
                destinationAddress: "0xabc"
            )
            XCTFail("Expected throw")
        } catch MockLimitSwapQuoteService.StubError.notStubbed {
            // expected
        } catch {
            XCTFail("Expected StubError.notStubbed, got \(error)")
        }
    }

    func testMarketPriceRecordsAssetPairsPerCall() async throws {
        let mock = MockLimitSwapQuoteService()
        mock.marketPriceResult = .success(0)

        _ = try await mock.fetchCurrentMarketPrice(
            sourceAsset: "BTC.BTC",
            sourceAmount: 1,
            sourceDecimals: 8,
            targetAsset: "ETH.ETH",
            targetDecimals: 18,
            destinationAddress: "0xabc"
        )
        _ = try await mock.fetchCurrentMarketPrice(
            sourceAsset: "ETH.ETH",
            sourceAmount: 1,
            sourceDecimals: 18,
            targetAsset: "BTC.BTC",
            targetDecimals: 8,
            destinationAddress: "bc1q..."
        )

        XCTAssertEqual(mock.marketPriceCallCount, 2)
        XCTAssertEqual(mock.marketPriceQueries.count, 2)
        XCTAssertEqual(mock.marketPriceQueries[0].sourceAsset, "BTC.BTC")
        XCTAssertEqual(mock.marketPriceQueries[1].sourceAsset, "ETH.ETH")
    }
}
