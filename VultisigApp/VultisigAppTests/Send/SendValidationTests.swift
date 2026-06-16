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
        // Leaves 0.005 DOT remainder — below the 0.01-DOT Asset Hub ED, but > 0.
        XCTAssertTrue(SendCryptoLogic.canBeReaped(coin: dot, amount: amount("9.995"), gas: .zero))
    }

    func testCanBeReapedFalseForPolkadotWhenRemainderAboveExistentialDeposit() {
        let dot = makeCoin(.polkadot, ticker: Chain.polkadot.ticker, decimals: 10, isNative: true,
                           rawBalance: "100000000000") // 10 DOT
        // Leaves 9 DOT remainder — well above the 0.01-DOT ED.
        XCTAssertFalse(SendCryptoLogic.canBeReaped(coin: dot, amount: "1", gas: .zero))
    }

    func testCanBeReapedFalseForPolkadotWhenRemainderEqualsExistentialDeposit() {
        let dot = makeCoin(.polkadot, ticker: Chain.polkadot.ticker, decimals: 10, isNative: true,
                           rawBalance: "100000000000") // 10 DOT
        // Leaves exactly 0.01 DOT remainder — `transfer_keep_alive` permits ED,
        // so this is NOT reaped. Confirms the max-send (balance − fee − ED) path
        // settling at exactly ED is allowed.
        XCTAssertFalse(SendCryptoLogic.canBeReaped(coin: dot, amount: amount("9.99"), gas: .zero))
    }

    func testCanBeReapedFalseForBittensorTAO() {
        // Bittensor shares chainType == .Polkadot but signs transfer_allow_death,
        // so it has no enforced ED and must never be blocked or reserve ED.
        let tao = makeCoin(.bittensor, ticker: Chain.bittensor.ticker, decimals: 9, isNative: true,
                           rawBalance: "1000000000") // 1 TAO
        XCTAssertFalse(SendCryptoLogic.canBeReaped(coin: tao, amount: amount("0.999999999"), gas: BigInt(1)))
    }

    func testExistentialDepositReservedForPolkadotZeroForTAO() {
        let dot = makeCoin(.polkadot, ticker: Chain.polkadot.ticker, decimals: 10, isNative: true)
        let tao = makeCoin(.bittensor, ticker: Chain.bittensor.ticker, decimals: 9, isNative: true)
        // Asset Hub native-DOT ED is 0.01 DOT = 100_000_000 plancks (10 decimals).
        XCTAssertEqual(SendCryptoLogic.existentialDeposit(for: dot), BigInt(100_000_000))
        XCTAssertEqual(PolkadotHelper.defaultExistentialDeposit, BigInt(100_000_000))
        // TAO (allow_death) reserves nothing.
        XCTAssertEqual(SendCryptoLogic.existentialDeposit(for: tao), .zero)
    }

    func testComputeMaxAmountReservesExistentialDepositForPolkadot() {
        let dot = makeCoin(.polkadot, ticker: Chain.polkadot.ticker, decimals: 10, isNative: true,
                           rawBalance: "100000000000") // 10 DOT
        let fee = BigInt(100_000_000) // 0.01 DOT fee
        // max = balance − fee − ED = 10 − 0.01 − 0.01 = 9.98 DOT
        let maxAmount = SendCryptoLogic.computeMaxAmount(coin: dot, fee: fee)
        XCTAssertEqual(maxAmount.toDecimal(), amount("9.98").toDecimal())
        // And that max-send must NOT be reaped (remainder == ED, allowed).
        XCTAssertFalse(SendCryptoLogic.canBeReaped(coin: dot, amount: maxAmount, gas: fee))
    }

    func testComputeMaxAmountDoesNotReserveExistentialDepositForTAO() {
        let tao = makeCoin(.bittensor, ticker: Chain.bittensor.ticker, decimals: 9, isNative: true,
                           rawBalance: "1000000000") // 1 TAO
        let fee = BigInt(1_000_000) // 0.001 TAO
        // No ED reserve for allow_death: max = balance − fee = 0.999 TAO.
        let maxAmount = SendCryptoLogic.computeMaxAmount(coin: tao, fee: fee)
        XCTAssertEqual(maxAmount.toDecimal(), amount("0.999").toDecimal())
    }

    func testSubExistentialDepositSendToRecipientIsAllowed() {
        // A sub-ED amount to the recipient is the user's choice and must NOT be
        // blocked, regardless of whether the target account already exists.
        // Only the sender-reaping guard applies, and here the sender keeps a
        // large remainder, so canBeReaped is false.
        let dot = makeCoin(.polkadot, ticker: Chain.polkadot.ticker, decimals: 10, isNative: true,
                           rawBalance: "100000000000") // 10 DOT
        // Sending 0.005 DOT (< 0.01 DOT ED) leaves ~9.995 DOT for the sender.
        XCTAssertFalse(SendCryptoLogic.canBeReaped(coin: dot, amount: amount("0.005"), gas: .zero))
    }

    func testCanBeReapedUsesFeeNotGasForExistentialDepositReserve() {
        // The call sites (SendDetailsViewModel.validateBalance and
        // SendCryptoVerifyLogic.validateBalanceWithFee) must pass the planned
        // transaction `fee` into the `gas:` parameter — not the raw per-unit
        // `gas`. This test pins that distinction: with the same amount, the
        // real fee tips the remainder below ED (reaped) while the tiny raw gas
        // would leave it above ED (not reaped).
        let dot = makeCoin(.polkadot, ticker: Chain.polkadot.ticker, decimals: 10, isNative: true,
                           rawBalance: "100000000000") // 10 DOT
        let amountStr = amount("9.985") // leaves 0.015 DOT before fee/gas deduction
        let fee = BigInt(100_000_000) // 0.01 DOT planned fee
        let rawGas = BigInt(1_000)    // negligible per-unit gas
        // With the fee: remainder = 0.015 − 0.01 = 0.005 DOT < 0.01 ED → reaped.
        XCTAssertTrue(SendCryptoLogic.canBeReaped(coin: dot, amount: amountStr, gas: fee))
        // With the raw gas: remainder ≈ 0.015 DOT > 0.01 ED → NOT reaped.
        // Passing gas here would wrongly let a reaping send through.
        XCTAssertFalse(SendCryptoLogic.canBeReaped(coin: dot, amount: amountStr, gas: rawGas))
    }

    func testCanBeReapedTrueForRippleWhenRemainderBelowExistentialDeposit() {
        let xrp = makeCoin(.ripple, ticker: Chain.ripple.ticker, decimals: 6, isNative: true,
                           rawBalance: "11000000") // 11 XRP
        XCTAssertTrue(SendCryptoLogic.canBeReaped(coin: xrp, amount: amount("10.999"), gas: BigInt(1)))
    }

    // MARK: - isBelowMinimumSendAmount

    func testIsBelowCardanoMinimumTrueWhenNativeAdaBelowFloor() {
        let ada = makeCoin(.cardano, ticker: "ADA", decimals: 6, isNative: true,
                           rawBalance: "10000000") // 10 ADA
        // 1.0 ADA < 1.4 ADA protocol minimum UTXO floor.
        XCTAssertTrue(SendCryptoLogic.isBelowMinimumSendAmount(coin: ada, amount: "1"))
    }

    func testIsBelowCardanoMinimumFalseAtFloor() {
        let ada = makeCoin(.cardano, ticker: "ADA", decimals: 6, isNative: true,
                           rawBalance: "10000000") // 10 ADA
        // Exactly 1.4 ADA meets the minimum.
        XCTAssertFalse(SendCryptoLogic.isBelowMinimumSendAmount(coin: ada, amount: amount("1.4")))
    }

    func testIsBelowCardanoMinimumFalseAboveFloor() {
        let ada = makeCoin(.cardano, ticker: "ADA", decimals: 6, isNative: true,
                           rawBalance: "10000000")
        XCTAssertFalse(SendCryptoLogic.isBelowMinimumSendAmount(coin: ada, amount: "2"))
    }

    func testIsBelowCardanoMinimumTrueForMaxSendBelowFloor() {
        // For a MAX send, `amount` is the computed recipient output (balance −
        // fee). When the whole vault holds less than the floor the MAX output is
        // still below the minimum and must be blocked, not exempted.
        let ada = makeCoin(.cardano, ticker: "ADA", decimals: 6, isNative: true,
                           rawBalance: "1300000") // 1.3 ADA total
        let fee = BigInt(170_000) // ~0.17 ADA
        let maxAmount = SendCryptoLogic.computeMaxAmount(coin: ada, fee: fee) // ~1.13 ADA
        XCTAssertTrue(SendCryptoLogic.isBelowMinimumSendAmount(coin: ada, amount: maxAmount))
    }

    func testIsBelowCardanoMinimumFalseForMaxSendAboveFloor() {
        let ada = makeCoin(.cardano, ticker: "ADA", decimals: 6, isNative: true,
                           rawBalance: "10000000") // 10 ADA total
        let fee = BigInt(170_000)
        let maxAmount = SendCryptoLogic.computeMaxAmount(coin: ada, fee: fee) // ~9.83 ADA
        XCTAssertFalse(SendCryptoLogic.isBelowMinimumSendAmount(coin: ada, amount: maxAmount))
    }

    func testIsBelowCardanoMinimumFalseForNonNativeToken() {
        // Cardano native tokens (CNT) carry their own ADA floor on the bundled
        // output and are exempt from the native-ADA minimum.
        let cnt = makeCoin(.cardano, ticker: "SNEK", decimals: 0, isNative: false,
                           rawBalance: "1000")
        XCTAssertFalse(SendCryptoLogic.isBelowMinimumSendAmount(coin: cnt, amount: "1"))
    }

    func testIsBelowCardanoMinimumFalseForOtherChains() {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true,
                           rawBalance: "100000000")
        XCTAssertFalse(SendCryptoLogic.isBelowMinimumSendAmount(coin: btc, amount: "0.00001"))
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
        setPrice(2_000, for: eth)
        XCTAssertNil(SendCryptoLogic.fiatToCoinAmount(fiat: "", coin: eth))
    }

    func testFiatToCoinAmountReturnsNilForZeroInput() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        setPrice(2_000, for: eth)
        XCTAssertNil(SendCryptoLogic.fiatToCoinAmount(fiat: "0", coin: eth))
    }

    func testFiatToCoinAmountReturnsNilWhenCoinHasNoPrice() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        // priceRate defaults to 0 — guard against divide-by-zero.
        XCTAssertNil(SendCryptoLogic.fiatToCoinAmount(fiat: "100", coin: eth))
    }

    func testFiatToCoinAmountDividesByCoinPrice() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        setPrice(2_000, for: eth)
        // $100 / $2000/ETH = 0.05 ETH
        let result = SendCryptoLogic.fiatToCoinAmount(fiat: "100", coin: eth)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.toDecimal(), Decimal(string: "0.05"))
    }

    // MARK: - coinAmountToFiat

    func testCoinAmountToFiatReturnsNilForEmptyInput() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        setPrice(2_000, for: eth)
        XCTAssertNil(SendCryptoLogic.coinAmountToFiat(amount: "", coin: eth))
    }

    func testCoinAmountToFiatReturnsNilForZeroInput() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        setPrice(2_000, for: eth)
        XCTAssertNil(SendCryptoLogic.coinAmountToFiat(amount: "0", coin: eth))
    }

    func testCoinAmountToFiatMultipliesByCoinPrice() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        setPrice(2_000, for: eth)
        // 0.5 ETH * $2000 = $1000
        let result = SendCryptoLogic.coinAmountToFiat(amount: "0.5", coin: eth)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.toDecimal(), Decimal(string: "1000"))
    }

    func testCoinAmountToFiatTruncatesToTwoDecimals() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        setPrice(1_234.5678, for: eth)
        // 0.0001 * 1234.5678 ≈ 0.12346 → 0.12 after truncated(toPlaces: 2)
        let result = SendCryptoLogic.coinAmountToFiat(amount: "0.0001", coin: eth)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.toDecimal(), Decimal(string: "0.12"))
    }

    // MARK: - Helpers

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool, rawBalance: String = "0") -> Coin {
        var asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        asset.priceProviderId = "send-validation-\(ticker)-\(UUID().uuidString)"
        let coin = Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
        coin.rawBalance = rawBalance
        return coin
    }

    /// Re-renders a canonical dot-decimal amount string into the current
    /// locale's decimal separator. The send helpers parse with
    /// `Locale.current` first, so a literal like "0.005" misparses under
    /// comma-decimal locales (e.g. en_AR on a dev machine, where "." reads as a
    /// grouping separator). Building the amount with the active separator keeps
    /// these unit tests deterministic across locales.
    private func amount(_ canonical: String) -> String {
        let separator = Locale.current.decimalSeparator ?? "."
        return canonical.replacingOccurrences(of: ".", with: separator)
    }

    private func setPrice(_ value: Double, for coin: Coin) {
        let cryptoId = RateProvider.cryptoId(for: coin.toCoinMeta()).id
        try? RateProvider.shared.save(rates: [
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: cryptoId, value: value)
        ])
    }
}
