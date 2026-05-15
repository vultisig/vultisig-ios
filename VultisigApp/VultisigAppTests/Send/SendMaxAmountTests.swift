//
//  SendMaxAmountTests.swift
//  VultisigAppTests
//
//  Coverage for SendCryptoLogic.computeMaxAmount and applyPercentage —
//  the per-chain async fetches stay in the interactor; only the math
//  lives here.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SendMaxAmountTests: XCTestCase {

    // MARK: - computeMaxAmount

    func testComputeMaxAmountSubtractsFeeFromBalanceForNativeEVM() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "1000000000000000000") // 1 ETH
        // Fee = 0.01 ETH (1e16 wei).
        let amount = SendCryptoLogic.computeMaxAmount(coin: eth, fee: BigInt(stringLiteral: "10000000000000000"))
        XCTAssertEqual(amount.toDecimal(), Decimal(string: "0.99"))
    }

    func testComputeMaxAmountReturnsFullBalanceWhenFeeZero() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true,
                           rawBalance: "100000000") // 1 BTC
        let amount = SendCryptoLogic.computeMaxAmount(coin: btc, fee: .zero)
        XCTAssertEqual(amount.toDecimal(), Decimal(string: "1"))
    }

    func testComputeMaxAmountReturnsZeroWhenFeeExceedsBalance() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "1000") // 1000 wei
        let amount = SendCryptoLogic.computeMaxAmount(coin: eth, fee: BigInt(10_000))
        XCTAssertEqual(amount.toDecimal(), .zero)
    }

    func testComputeMaxAmountForERC20IgnoresGasCoinFee() {
        // ERC20 max-send: token balance is the whole pool; gas is paid in
        // native and fed in as fee=0 here.
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false,
                            rawBalance: "200000000") // 200 USDC
        let amount = SendCryptoLogic.computeMaxAmount(coin: usdc, fee: .zero)
        XCTAssertEqual(amount.toDecimal(), Decimal(string: "200"))
    }

    func testComputeMaxAmountDoesNotUseGroupingSeparators() {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false,
                            rawBalance: "1000000000") // 1000 USDC

        let amount = SendCryptoLogic.computeMaxAmount(coin: usdc, fee: .zero)

        XCTAssertEqual(amount, "1000")
        XCTAssertFalse(amount.contains(Locale.current.groupingSeparator ?? ","))
    }

    func testComputeMaxAmountCardanoSubtractsLovelaceFee() {
        let ada = makeCoin(.cardano, ticker: "ADA", decimals: 6, isNative: true,
                           rawBalance: "10000000") // 10 ADA
        // Plan fee 0.5 ADA = 500_000 lovelace.
        let amount = SendCryptoLogic.computeMaxAmount(coin: ada, fee: BigInt(500_000))
        XCTAssertEqual(amount.toDecimal(), Decimal(string: "9.5"))
    }

    // MARK: - applyPercentage

    func testApplyPercentageScalesAmountLinearly() {
        XCTAssertEqual(
            SendCryptoLogic.applyPercentage(maxAmount: "1.0", percentage: 50, coinDecimals: 8).toDecimal(),
            Decimal(string: "0.5")
        )
        XCTAssertEqual(
            SendCryptoLogic.applyPercentage(maxAmount: "1.0", percentage: 25, coinDecimals: 8).toDecimal(),
            Decimal(string: "0.25")
        )
        XCTAssertEqual(
            SendCryptoLogic.applyPercentage(maxAmount: "1.0", percentage: 75, coinDecimals: 8).toDecimal(),
            Decimal(string: "0.75")
        )
    }

    func testApplyPercentageReturnsZeroForZeroPercentage() {
        XCTAssertEqual(
            SendCryptoLogic.applyPercentage(maxAmount: "1.0", percentage: 0, coinDecimals: 8).toDecimal(),
            .zero
        )
    }

    func testApplyPercentageDoesNotUseGroupingSeparators() {
        let amount = SendCryptoLogic.applyPercentage(maxAmount: "1000", percentage: 50, coinDecimals: 6)

        XCTAssertEqual(amount, "500")
        XCTAssertFalse(amount.contains(Locale.current.groupingSeparator ?? ","))
    }

    // MARK: - Helpers

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool, rawBalance: String = "0") -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        let coin = Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
        coin.rawBalance = rawBalance
        return coin
    }
}
