//
//  KyberSwapQuoteTests.swift
//  VultisigAppTests
//
//  Pins the fee-overlay-free behavior on iOS: `routeSummary.gas` flows
//  through verbatim and `routeSummary.gasPrice` is used un-floored. Two
//  iOS-only overlays (a 2.0x gas multiplier and a 1 gwei gas-price floor)
//  used to compound to ~13x over the extension's displayed fee for the
//  same KyberSwap route. Both have been removed; these tests guard
//  against regression.
//

import BigInt
import XCTest
@testable import VultisigApp

final class KyberSwapQuoteTests: XCTestCase {

    // MARK: - gas (formerly gasForChain)

    func testGasReturnsApiValueUnmultiplied() {
        // Real KyberSwap response on Ethereum at 2026-05-26: routeSummary.gas = 1_892_998.
        // Before the fix iOS multiplied by 2.0 on Ethereum and returned 3_785_996.
        let quote = makeQuote(gas: "1892998")
        XCTAssertEqual(quote.gas, 1_892_998)
    }

    func testGasOnLowMultiplierChainStillReturnsApiValue() {
        // Before the fix non-mainnet EVM chains used a 1.6x multiplier
        // (e.g. zkSync, Linea). Now every chain uses the API value as-is.
        let quote = makeQuote(gas: "500000")
        XCTAssertEqual(quote.gas, 500_000)
    }

    func testGasFallsBackToDefaultWhenUnparseable() {
        // Defensive: a malformed `gas` field falls back to the EVM swap default,
        // never to a hardcoded 600_000 or any chain-specific value.
        let quote = makeQuote(gas: "not-a-number")
        XCTAssertEqual(quote.gas, Int64(EVMHelper.defaultETHSwapGasUnit))
    }

    // MARK: - parseGasPriceWei

    func testParseGasPriceWeiPassesSubGweiValueThrough() {
        // KyberSwap returned 0.1286 gwei (= 128_575_467 wei) at the time of
        // the bug report. Before the fix iOS floored this to 1 gwei
        // (1_000_000_000 wei), a 7.78x inflation. The fix removes the floor.
        let result = KyberSwapQuote.parseGasPriceWei("128575467")
        XCTAssertEqual(result, BigInt("128575467"))
    }

    func testParseGasPriceWeiFallsBackToOneGweiWhenNil() {
        // The defensive fallback (1 gwei) still fires when the aggregator
        // returns no value at all.
        let result = KyberSwapQuote.parseGasPriceWei(nil)
        XCTAssertEqual(result, BigInt("1000000000"))
    }

    func testParseGasPriceWeiFallsBackToOneGweiWhenUnparseable() {
        // Same fallback when the value is non-numeric.
        let result = KyberSwapQuote.parseGasPriceWei("nonsense")
        XCTAssertEqual(result, BigInt("1000000000"))
    }

    func testParseGasPriceWeiHonoursMultiGweiResponse() {
        // Sanity: high-congestion responses pass through unchanged.
        let result = KyberSwapQuote.parseGasPriceWei("25000000000") // 25 gwei
        XCTAssertEqual(result, BigInt("25000000000"))
    }

    // MARK: - Compound fee shape pinning

    func testFeeShapeMatchesApiValuesAtCurrentNetworkState() {
        // Recreates the bug-report swap (USDT -> USDC on Ethereum) at the
        // network state observed during the wiki investigation. Asserts the
        // recovered `gas * gasPrice` equals the API's own quote, NOT the
        // pre-fix iOS overlay output.
        let gas = makeQuote(gas: "1892998").gas
        let gasPriceWei = KyberSwapQuote.parseGasPriceWei("128575467")
        let fee = BigInt(gas) * gasPriceWei

        // 1_892_998 * 128_575_467 = 243_393_101_880_066 wei (~0.000243 ETH).
        // The pre-fix iOS path produced 3_785_996 * 1_000_000_000 =
        // 3_785_996_000_000_000 wei (~0.003786 ETH), ~15.6x over.
        XCTAssertEqual(fee, BigInt("243393101880066"))
        XCTAssertLessThan(fee, BigInt("500000000000000")) // < 0.0005 ETH
    }

    // MARK: - Fixture

    private func makeQuote(gas: String, gasPrice: String? = "128575467") -> KyberSwapQuote {
        return KyberSwapQuote(
            code: 0,
            message: "",
            data: KyberSwapQuote.Data(
                amountIn: "14272184",
                amountInUsd: "14.256",
                amountOut: "14689000",
                amountOutUsd: "14.684",
                gas: gas,
                gasUsd: "0.413",
                data: "0x",
                routerAddress: "0x0000000000000000000000000000000000000000",
                transactionValue: "0",
                gasPrice: gasPrice
            ),
            requestId: "test-fixture"
        )
    }
}
