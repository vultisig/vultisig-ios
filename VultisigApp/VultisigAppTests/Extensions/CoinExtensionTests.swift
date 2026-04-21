//
//  CoinExtensionTests.swift
//  VultisigAppTests
//
//  Created by Gaston Mazzeo on 20/04/2026.
//

@testable import VultisigApp
import XCTest

@MainActor
final class CoinExtensionTests: XCTestCase {

    func test_isDefiOnly_trueForSTCY() {
        let coin = makeCoin(ticker: "STCY", chain: .thorChain, isNative: false)
        XCTAssertTrue(coin.isDefiOnly)
    }

    func test_isDefiOnly_caseInsensitive() {
        for ticker in ["stcy", "Stcy", "StCy", "STCY"] {
            let coin = makeCoin(ticker: ticker, chain: .thorChain, isNative: false)
            XCTAssertTrue(coin.isDefiOnly, "Expected \(ticker) to be DeFi-only")
        }
    }

    func test_isDefiOnly_falseForCommonTickers() {
        for ticker in ["BTC", "ETH", "RUNE", "TCY", "YRUNE", "YTCY", "USDC"] {
            let coin = makeCoin(ticker: ticker, chain: .thorChain, isNative: false)
            XCTAssertFalse(coin.isDefiOnly, "Expected \(ticker) not to be DeFi-only")
        }
    }

    func test_defiOnlyTickers_containsSTCY() {
        XCTAssertTrue(Coin.defiOnlyTickers.contains("STCY"))
    }

    func test_totalBalanceInFiatDecimal_emptyArrayReturnsZero() {
        let coins: [Coin] = []
        XCTAssertEqual(coins.totalBalanceInFiatDecimal, 0)
    }

    func test_totalBalanceInFiatDecimal_allDefiOnlyReturnsZero() {
        let coins = [
            makeCoin(ticker: "STCY", chain: .thorChain, isNative: false),
            makeCoin(ticker: "stcy", chain: .thorChain, isNative: false)
        ]
        XCTAssertEqual(coins.totalBalanceInFiatDecimal, 0)
    }

    func test_totalBalanceInFiatDecimal_skipsDefiOnlyBeforeFiatLookup() {
        let stcy = makeCoin(ticker: "STCY", chain: .thorChain, isNative: false)
        stcy.rawBalance = "999999999999999999"
        let coins = [stcy]
        XCTAssertEqual(
            coins.totalBalanceInFiatDecimal, 0,
            "DeFi-only coins must be filtered before any fiat conversion"
        )
    }

    func test_totalBalanceInFiatDecimal_filterRemovesOnlyDefiOnly() {
        let btc = makeCoin(ticker: "BTC", chain: .bitcoin, isNative: true)
        let rune = makeCoin(ticker: "RUNE", chain: .thorChain, isNative: true)
        let stcy = makeCoin(ticker: "STCY", chain: .thorChain, isNative: false)

        let filtered = [btc, rune, stcy].filter { !$0.isDefiOnly }
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains(where: { $0.ticker == "BTC" }))
        XCTAssertTrue(filtered.contains(where: { $0.ticker == "RUNE" }))
        XCTAssertFalse(filtered.contains(where: { $0.ticker == "STCY" }))
    }

    // MARK: - Helpers

    private func makeCoin(ticker: String, chain: Chain, isNative: Bool) -> Coin {
        let meta = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "",
            decimals: 8,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: isNative
        )
        return Coin(asset: meta, address: "test", hexPublicKey: "test")
    }
}
