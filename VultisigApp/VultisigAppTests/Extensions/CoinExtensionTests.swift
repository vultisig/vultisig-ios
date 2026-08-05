//
//  CoinExtensionTests.swift
//  VultisigAppTests
//
//  Created by Gaston Mazzeo on 20/04/2026.
//

@testable import VultisigApp
import BigInt
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

    // MARK: - balanceRaw

    /// Past `Int64` — about 9.223 on an 18-decimal asset — the shared decimal
    /// parser goes through `Double` and keeps 17 significant digits. Every
    /// digit of the vault's balance has to survive the read.
    func testBalanceRawReadsABalanceBeyondInt64Exactly() {
        // 99.999999999999999999 ETH — the lossy read rounds it to a flat 100.
        let raw = "99999999999999999999"
        let coin = makeCoin(ticker: "ETH", chain: .ethereum, isNative: true, decimals: 18, rawBalance: raw)

        XCTAssertEqual(coin.balanceRaw, BigInt(raw)!)
    }

    /// Reading a balance as LARGER than it is lets an affordability guard pass
    /// a send the chain then rejects at broadcast — after the signing ceremony
    /// has already run. The read may never overstate the vault.
    func testBalanceRawNeverReportsMoreThanTheVaultHolds() {
        for raw in ["9223372036854775808", "12345678901234567890", "99999999999999999999"] {
            let coin = makeCoin(ticker: "ETH", chain: .ethereum, isNative: true, decimals: 18, rawBalance: raw)
            XCTAssertLessThanOrEqual(coin.balanceRaw, BigInt(raw)!, "\(raw) was read as more than it is")
        }
    }

    /// A shape the exact integer read declines still reaches the shared parser
    /// rather than collapsing to a zero balance.
    func testBalanceRawFallsBackInsteadOfCollapsingToZero() {
        XCTAssertNil(BigInt("1e18"), "the exact integer read has to be what declines this shape")
        let coin = makeCoin(ticker: "ETH", chain: .ethereum, isNative: true, decimals: 18, rawBalance: "1e18")

        XCTAssertEqual(coin.balanceRaw, BigInt("1000000000000000000")!)
    }

    // MARK: - Helpers

    private func makeCoin(
        ticker: String,
        chain: Chain,
        isNative: Bool,
        decimals: Int = 8,
        rawBalance: String = "0"
    ) -> Coin {
        let meta = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "",
            decimals: decimals,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: isNative
        )
        let coin = Coin(asset: meta, address: "test", hexPublicKey: "test")
        coin.rawBalance = rawBalance
        return coin
    }
}
