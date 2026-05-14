//
//  SendValidationTests.swift
//  VultisigAppTests
//
//  Coverage for the primitive-based send-validation helpers — amountInRaw,
//  amountDecimal, isAmountExceeded, canBeReaped, isDeposit.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SendValidationTests: XCTestCase {

    // MARK: - Amount conversions

    func testAmountDecimalTruncatesToCoinDecimals() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        XCTAssertEqual(SendCryptoLogic.amountDecimal(coin: btc, amount: "0.123456789999"), Decimal(string: "0.12345678"))
    }

    func testAmountInRawScalesByDecimals() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        XCTAssertEqual(SendCryptoLogic.amountInRaw(coin: btc, amount: "1"), BigInt(100_000_000))
        XCTAssertEqual(SendCryptoLogic.amountInRaw(coin: btc, amount: "0.5"), BigInt(50_000_000))
    }

    func testGasDecimalConvertsBigIntToDecimal() {
        XCTAssertEqual(SendCryptoLogic.gasDecimal(gas: BigInt(1_500)), Decimal(1500))
    }

    // MARK: - isAmountExceeded

    func testIsAmountExceededFalseForTronStakingShortCircuit() {
        let trx = makeCoin(.tron, ticker: "TRX", decimals: 6, isNative: true, rawBalance: "0")
        XCTAssertFalse(SendCryptoLogic.isAmountExceeded(
            coin: trx, amount: "1000", sendMaxAmount: false,
            fee: BigInt(100), gas: BigInt(100), isStakingOperation: true
        ))
    }

    func testIsAmountExceededFalseWhenAmountPlusGasFitsForNativeEVM() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "1000000000000000000") // 1 ETH
        XCTAssertFalse(SendCryptoLogic.isAmountExceeded(
            coin: eth, amount: "0.5", sendMaxAmount: false,
            fee: .zero, gas: BigInt(1_000_000_000_000_000), isStakingOperation: false
        ))
    }

    func testIsAmountExceededTrueWhenAmountPlusGasOverflowsNativeEVM() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "1000000000000000000") // 1 ETH
        XCTAssertTrue(SendCryptoLogic.isAmountExceeded(
            coin: eth, amount: "1.0", sendMaxAmount: false,
            fee: .zero, gas: BigInt(1_000_000_000_000_000), isStakingOperation: false
        ))
    }

    func testIsAmountExceededUsesFeeNotGasForUTXO() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true,
                           rawBalance: "100000000") // 1 BTC
        // gas (sats/byte) = 50 — would not push over balance even at 100k bytes (5M sat).
        // fee (the planned UTXO fee) = 5_000_000 sats — pushes a 99M-sat send over balance.
        XCTAssertTrue(SendCryptoLogic.isAmountExceeded(
            coin: btc, amount: "0.99", sendMaxAmount: false,
            fee: BigInt(5_000_000), gas: BigInt(50), isStakingOperation: false
        ))
    }

    func testIsAmountExceededUsesFeeNotGasForCardano() {
        let ada = makeCoin(.cardano, ticker: "ADA", decimals: 6, isNative: true,
                           rawBalance: "10000000") // 10 ADA
        XCTAssertTrue(SendCryptoLogic.isAmountExceeded(
            coin: ada, amount: "9.9", sendMaxAmount: false,
            fee: BigInt(500_000), gas: BigInt(0), isStakingOperation: false
        ))
    }

    func testIsAmountExceededFalseForERC20WithinTokenBalance() {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false,
                            rawBalance: "200000000") // 200 USDC
        XCTAssertFalse(SendCryptoLogic.isAmountExceeded(
            coin: usdc, amount: "100", sendMaxAmount: false,
            fee: BigInt(1), gas: BigInt(1), isStakingOperation: false
        ))
    }

    func testIsAmountExceededTrueForERC20WhenAmountAlone() {
        // Non-native: only the token balance matters; gas/fee don't count
        // against the token balance.
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false,
                            rawBalance: "50000000") // 50 USDC
        XCTAssertTrue(SendCryptoLogic.isAmountExceeded(
            coin: usdc, amount: "100", sendMaxAmount: false,
            fee: .zero, gas: .zero, isStakingOperation: false
        ))
    }

    func testIsAmountExceededSendMaxUTXOComparesRawAmountToBalance() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true,
                           rawBalance: "100000000") // 1 BTC
        // sendMax + UTXO ignores `fee` for the comparison — the deducted-fee
        // amount is baked into the UI's max-amount calculation, not here.
        XCTAssertFalse(SendCryptoLogic.isAmountExceeded(
            coin: btc, amount: "1.0", sendMaxAmount: true,
            fee: BigInt(1_000_000), gas: BigInt(50), isStakingOperation: false
        ))
        XCTAssertTrue(SendCryptoLogic.isAmountExceeded(
            coin: btc, amount: "1.01", sendMaxAmount: true,
            fee: .zero, gas: .zero, isStakingOperation: false
        ))
    }

    // MARK: - canBeReaped

    func testCanBeReapedFalseForChainWithoutExistentialDeposit() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "1000000000000000000")
        XCTAssertFalse(SendCryptoLogic.canBeReaped(coin: eth, amount: "0.5", gas: .zero))
    }

    func testCanBeReapedTrueForPolkadotWhenRemainderBelowExistentialDeposit() {
        let dot = makeCoin(.polkadot, ticker: Chain.polkadot.ticker, decimals: 10, isNative: true,
                           rawBalance: "100000000000") // 10 DOT
        // Sending almost the entire balance with negligible gas leaves a tiny remainder.
        XCTAssertTrue(SendCryptoLogic.canBeReaped(coin: dot, amount: "9.99999999", gas: BigInt(1)))
    }

    func testCanBeReapedFalseForPolkadotWhenRemainderAboveExistentialDeposit() {
        let dot = makeCoin(.polkadot, ticker: Chain.polkadot.ticker, decimals: 10, isNative: true,
                           rawBalance: "100000000000") // 10 DOT
        XCTAssertFalse(SendCryptoLogic.canBeReaped(coin: dot, amount: "1", gas: .zero))
    }

    func testCanBeReapedTrueForRippleWhenRemainderBelowExistentialDeposit() {
        let xrp = makeCoin(.ripple, ticker: Chain.ripple.ticker, decimals: 6, isNative: true,
                           rawBalance: "11000000") // 11 XRP
        XCTAssertTrue(SendCryptoLogic.canBeReaped(coin: xrp, amount: "10.999", gas: BigInt(1)))
    }

    // MARK: - isDeposit

    func testIsDepositFalseWhenMemoEmpty() {
        let atom = makeCoin(.gaiaChain, ticker: "ATOM", decimals: 6, isNative: true)
        XCTAssertFalse(SendCryptoLogic.isDeposit(coin: atom, memoFunctionDictionary: [:]))
    }

    func testIsDepositTrueForCosmosWithMemo() {
        let atom = makeCoin(.gaiaChain, ticker: "ATOM", decimals: 6, isNative: true)
        XCTAssertTrue(SendCryptoLogic.isDeposit(coin: atom, memoFunctionDictionary: ["pool": "BTC.BTC"]))
    }

    func testIsDepositFalseForUTXOEvenWithMemo() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        XCTAssertFalse(SendCryptoLogic.isDeposit(coin: btc, memoFunctionDictionary: ["any": "value"]))
    }

    func testIsDepositFalseForRippleEvenWithMemo() {
        let xrp = makeCoin(.ripple, ticker: "XRP", decimals: 6, isNative: true)
        XCTAssertFalse(SendCryptoLogic.isDeposit(coin: xrp, memoFunctionDictionary: ["any": "value"]))
    }

    func testIsDepositFalseForSolanaEvenWithMemo() {
        let sol = makeCoin(.solana, ticker: "SOL", decimals: 9, isNative: true)
        XCTAssertFalse(SendCryptoLogic.isDeposit(coin: sol, memoFunctionDictionary: ["any": "value"]))
    }

    // MARK: - fiatToCoinAmount

    func testFiatToCoinAmountReturnsNilForEmptyInput() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        eth.priceRate = 2_000
        XCTAssertNil(SendCryptoLogic.fiatToCoinAmount(fiat: "", coin: eth))
    }

    func testFiatToCoinAmountReturnsNilForZeroInput() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        eth.priceRate = 2_000
        XCTAssertNil(SendCryptoLogic.fiatToCoinAmount(fiat: "0", coin: eth))
    }

    func testFiatToCoinAmountReturnsNilWhenCoinHasNoPrice() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        // priceRate defaults to 0 — guard against divide-by-zero.
        XCTAssertNil(SendCryptoLogic.fiatToCoinAmount(fiat: "100", coin: eth))
    }

    func testFiatToCoinAmountDividesByCoinPrice() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        eth.priceRate = 2_000
        // $100 / $2000/ETH = 0.05 ETH
        let result = SendCryptoLogic.fiatToCoinAmount(fiat: "100", coin: eth)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.toDecimal(), Decimal(string: "0.05"))
    }

    // MARK: - coinAmountToFiat

    func testCoinAmountToFiatReturnsNilForEmptyInput() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        eth.priceRate = 2_000
        XCTAssertNil(SendCryptoLogic.coinAmountToFiat(amount: "", coin: eth))
    }

    func testCoinAmountToFiatReturnsNilForZeroInput() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        eth.priceRate = 2_000
        XCTAssertNil(SendCryptoLogic.coinAmountToFiat(amount: "0", coin: eth))
    }

    func testCoinAmountToFiatMultipliesByCoinPrice() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        eth.priceRate = 2_000
        // 0.5 ETH * $2000 = $1000
        let result = SendCryptoLogic.coinAmountToFiat(amount: "0.5", coin: eth)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.toDecimal(), Decimal(string: "1000"))
    }

    func testCoinAmountToFiatTruncatesToTwoDecimals() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        eth.priceRate = 1_234.5678
        // 0.0001 * 1234.5678 ≈ 0.12346 → 0.12 after truncated(toPlaces: 2)
        let result = SendCryptoLogic.coinAmountToFiat(amount: "0.0001", coin: eth)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.toDecimal(), Decimal(string: "0.12"))
    }

    // MARK: - Helpers

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool, rawBalance: String = "0") -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        let coin = Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
        coin.rawBalance = rawBalance
        return coin
    }
}
