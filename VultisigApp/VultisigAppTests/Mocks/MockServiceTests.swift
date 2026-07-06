//
//  MockServiceTests.swift
//  VultisigAppTests
//
//  Sanity tests for the §0.B service mocks: each mock returns its stubbed
//  value, increments its call counter, and captures the last input. Light by
//  design — the mocks themselves are simple enough that this is mostly a
//  guard against accidental drift in the protocol surface.
//

import XCTest
@testable import VultisigApp

@MainActor
final class MockServiceTests: XCTestCase {

    func testMockBalanceServiceTracksCallsAndCoin() async {
        let mock = MockBalanceService()
        XCTAssertEqual(mock.updateBalanceCallCount, 0)
        XCTAssertNil(mock.lastUpdatedCoin)

        await mock.updateBalance(for: .example)

        XCTAssertEqual(mock.updateBalanceCallCount, 1)
        XCTAssertEqual(mock.lastUpdatedCoin, .example)
    }

    func testMockFastVaultServiceReturnsStub() async {
        let mock = MockFastVaultService()
        mock.stubbedExist = true

        let result = await mock.exist(pubKeyECDSA: "abc")

        XCTAssertTrue(result)
        XCTAssertEqual(mock.existCallCount, 1)
        XCTAssertEqual(mock.lastQueriedPubKey, "abc")
    }

    func testMockBlockChainServiceReturnsStubbedSpecific() async throws {
        let mock = MockBlockChainService(
            stubbedResult: .success(.Cosmos(accountNumber: 1, sequence: 0, gas: 200_000, transactionType: 0, ibcDenomTrace: nil, gasLimit: nil))
        )

        let specific = try await mock.fetchSwapBlockChainSpecific(
            fromCoin: .example,
            toCoin: .example,
            fromAmount: 0.1,
            quote: nil
        )

        if case .Cosmos(let accountNumber, _, _, _, _, _) = specific {
            XCTAssertEqual(accountNumber, 1)
        } else {
            XCTFail("Expected Cosmos variant")
        }
        XCTAssertEqual(mock.fetchSwapCallCount, 1)
        XCTAssertEqual(mock.lastFromAmount, 0.1)
    }

    func testMockBlockChainServiceThrowsStubbedError() async {
        let mock = MockBlockChainService(stubbedResult: .failure(StubError.failed))

        do {
            _ = try await mock.fetchSwapBlockChainSpecific(
                fromCoin: .example,
                toCoin: .example,
                fromAmount: 0,
                quote: nil
            )
            XCTFail("Expected throw")
        } catch {
            XCTAssertEqual(error as? StubError, .failed)
        }
        XCTAssertEqual(mock.fetchSwapCallCount, 1)
    }

    func testMockQuoteServiceThrowsStubbedError() async {
        let mock = MockQuoteService(stubbedResult: .failure(StubError.failed))

        do {
            _ = try await mock.fetchQuote(
                amount: 1,
                fromCoin: .example,
                toCoin: .example,
                isAffiliate: true,
                referredCode: "",
                vultTierDiscount: 0
            )
            XCTFail("Expected throw")
        } catch {
            XCTAssertEqual(error as? StubError, .failed)
        }
        XCTAssertEqual(mock.fetchQuoteCallCount, 1)
    }
}

private enum StubError: Error, Equatable {
    case failed
}
