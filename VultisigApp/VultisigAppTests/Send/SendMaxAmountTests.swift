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

    // MARK: - Full-precision max (no unit-of-last-place dust left behind)

    func testTokenMaxFillsFullBalance() {
        // USDT/USDC carry 6 decimals. Max must fill every one of them —
        // truncating to 5 stranded the last digit (100.12345) on every send.
        let usdt = makeCoin(.ethereum, ticker: "USDT", decimals: 6, isNative: false,
                            rawBalance: "100123456") // 100.123456 USDT
        let amount = SendCryptoLogic.computeMaxAmount(coin: usdt, fee: .zero)
        XCTAssertEqual(amount.toDecimal(), Decimal(string: "100.123456"))
    }

    func testCardanoMaxFillsFullBalance() {
        let ada = makeCoin(.cardano, ticker: "ADA", decimals: 6, isNative: true,
                           rawBalance: "10123456") // 10.123456 ADA
        let amount = SendCryptoLogic.computeMaxAmount(coin: ada, fee: .zero)
        XCTAssertEqual(amount.toDecimal(), Decimal(string: "10.123456"))
    }

    func testBitcoinMaxFillsFullBalanceToEightDecimals() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true,
                           rawBalance: "12345678") // 0.12345678 BTC
        let amount = SendCryptoLogic.computeMaxAmount(coin: btc, fee: .zero)
        XCTAssertEqual(amount.toDecimal(), Decimal(string: "0.12345678"))
    }

    func testNativeMaxWithFeeEqualsBalanceMinusFeeExactly() {
        let atom = makeCoin(.gaiaChain, ticker: "ATOM", decimals: 6, isNative: true,
                            rawBalance: "10123456") // 10.123456 ATOM
        let fee = BigInt(5_000) // 0.005 ATOM in uatom
        let amount = SendCryptoLogic.computeMaxAmount(coin: atom, fee: fee)
        // balance − fee, to the last unit: 10123456 − 5000 = 10118456 uatom.
        XCTAssertEqual(amount.toDecimal(), Decimal(string: "10.118456"))
    }

    func testTerraClassicMaxFillsFullPrecisionAfterBurnTax() {
        // Terra Classic bypasses getMaxValue for the burn-tax fixed point:
        // max = (balance − baseGasFee) / (1 + rate), rate = 0.5%.
        // 100 LUNC / 1.005 = 99.5024875621… → 99.502487 at full 6-dp precision.
        let lunc = makeCoin(.terraClassic, ticker: "LUNC", decimals: 6, isNative: true,
                            rawBalance: "100000000") // 100 LUNC
        let amount = SendCryptoLogic.computeMaxAmount(coin: lunc, fee: .zero)
        XCTAssertEqual(amount.toDecimal(), Decimal(string: "99.502487"))
    }

    func testComputeMaxAmountCapsDisplayAtEightDecimals() {
        // Deliberate and pre-existing: the amount written into the input field
        // is formatted at min(8, decimals), so an 18-decimal chain shows 8 dp
        // rather than rendering a wei-precision string in the UI. The residue
        // is sub-1e-8; the full precision is still available at the Coin level
        // (see the test below). Pinned so the cap reads as intentional.
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "1234567891234567890") // 1.23456789123456789 ETH
        let amount = SendCryptoLogic.computeMaxAmount(coin: eth, fee: .zero)
        XCTAssertEqual(amount.toDecimal(), Decimal(string: "1.23456789"))
    }

    func testGetMaxValueKeepsPrecisionBeyondDisplayCap() {
        // computeMaxAmount formats at min(8, decimals), so an 18-decimal chain
        // can only be observed at the Coin level. Pin full precision there.
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "1000000000000123456") // 1.000000000000123456 ETH
        XCTAssertEqual(eth.getMaxValue(.zero), Decimal(string: "1.000000000000123456"))
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
