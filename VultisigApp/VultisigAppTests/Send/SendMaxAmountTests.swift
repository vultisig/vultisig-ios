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

    // MARK: - verifyMaxCandidateRaw (Verify-screen native-Max re-derivation)

    func testVerifyMaxCandidateRawNonTerraSubtractsFeeWithoutClamping() {
        // Non-Terra native Max keeps `balance − fee − ED` verbatim; the
        // previous amount never clamps it (ED = 0 for ETH).
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "1000000000000000000") // 1 ETH
        let fee = BigInt(stringLiteral: "10000000000000000") // 0.01 ETH
        let candidate = SendCryptoLogic.verifyMaxCandidateRaw(
            coin: eth,
            fee: fee,
            previousAmountRaw: BigInt(1) // absurdly small: proves no clamp off Terra
        )
        XCTAssertEqual(candidate, BigInt(stringLiteral: "990000000000000000")) // 0.99 ETH
    }

    func testVerifyMaxCandidateRawTerraClassicClampsToDetailsAmount() {
        // Terra Classic: `balance − fee` overshoots the Details amount by the
        // truncation residue; the clamp pins it back to the spendable amount.
        let lunc = makeCoin(.terraClassic, ticker: "LUNC", decimals: 6, isNative: true,
                            rawBalance: "8497702")
        let baseGas = BigInt(TerraClassicTax.ulunaBaseGas)
        let previousAmountRaw = BigInt(200) // Details amount A = floor(202 / 1.005)
        let verifyFee = baseGas + TerraClassicTax.burnTax(amount: previousAmountRaw, rate: TerraClassicTax.fallbackBurnTaxRate)
        // balance − verifyFee = 8497702 − 8497501 = 201 (one uluna over A).
        let candidate = SendCryptoLogic.verifyMaxCandidateRaw(
            coin: lunc,
            fee: verifyFee,
            previousAmountRaw: previousAmountRaw
        )
        XCTAssertEqual(candidate, previousAmountRaw) // clamped from 201 down to 200
    }

    func testVerifyMaxCandidateRawTerraClassicKeepsCandidateWhenFeeGrew() {
        // If the refetched fee is high enough that `balance − fee` falls below
        // the Details amount, the smaller candidate is kept (it owes no more
        // tax than the Details amount, so it stays spendable).
        let lunc = makeCoin(.terraClassic, ticker: "LUNC", decimals: 6, isNative: true,
                            rawBalance: "9000000")
        let candidate = SendCryptoLogic.verifyMaxCandidateRaw(
            coin: lunc,
            fee: BigInt(600000), // leaves 8_400_000
            previousAmountRaw: BigInt(8_500_000) // larger than balance − fee
        )
        XCTAssertEqual(candidate, BigInt(8_400_000)) // not clamped up to the previous amount
    }

    func testTerraClassicVerifyMaxNeverUnderfundsAcrossSweptBalances() {
        // Regression for the 1-uluna underfunding: sweep a contiguous balance
        // range and assert the re-derived Verify amount is always spendable —
        // `amount + baseGas + burnTax(amount)` never exceeds the balance — while
        // confirming the pre-fix `balance − fee` formula did overshoot.
        let baseGas = BigInt(TerraClassicTax.ulunaBaseGas)
        let rate = TerraClassicTax.fallbackBurnTaxRate
        let lunc = makeCoin(.terraClassic, ticker: "LUNC", decimals: 6, isNative: true)

        func signedCost(_ amount: BigInt) -> BigInt {
            baseGas + amount + TerraClassicTax.burnTax(amount: amount, rate: rate)
        }

        let start = baseGas + 1
        let count = 4000
        var oldUnderfunded = 0
        var newUnderfunded = 0

        for offset in 0..<count {
            let balance = start + BigInt(offset)
            lunc.rawBalance = balance.description

            // Details-screen amount A: fee = baseGas only (no amount known yet).
            let detailsAmountStr = SendCryptoLogic.computeMaxAmount(coin: lunc, fee: baseGas)
            let aRaw = SendCryptoLogic.amountInRaw(coin: lunc, amount: detailsAmountStr)
            guard aRaw > 0 else { continue }

            // Verify refetches the fee with amount = A → embeds burnTax(A).
            let verifyFee = baseGas + TerraClassicTax.burnTax(amount: aRaw, rate: rate)

            // Pre-fix re-derivation (ED = 0 for Terra Classic).
            let oldCandidate = balance - verifyFee
            if oldCandidate > 0, signedCost(oldCandidate) > balance {
                oldUnderfunded += 1
            }

            // Re-derivation under test.
            let newCandidate = SendCryptoLogic.verifyMaxCandidateRaw(
                coin: lunc,
                fee: verifyFee,
                previousAmountRaw: aRaw
            )
            guard newCandidate > 0 else { continue }
            if signedCost(newCandidate) > balance {
                newUnderfunded += 1
            }
            XCTAssertLessThanOrEqual(
                newCandidate, aRaw,
                "verify amount \(newCandidate) exceeded the spendable Details amount \(aRaw) at balance \(balance)"
            )
        }

        XCTAssertGreaterThan(oldUnderfunded, 0, "sweep did not reproduce the pre-fix underfunding — test is not exercising the bug")
        XCTAssertEqual(newUnderfunded, 0, "clamped re-derivation still underfunded \(newUnderfunded) of \(count) balances")
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
