//
//  GenericSwapStatedZeroFeeTests.swift
//  VultisigAppTests
//
//  `EVMQuote.Transaction.swapFee` carries three states: absent (nil, nothing
//  on the wire, no row anywhere), a stated zero ("0" plus coin context, a
//  $0.00 row on both devices) and a stated amount. These tests pin the model
//  and the readers that turn it into the co-signer's fee row.
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class GenericSwapStatedZeroFeeTests: XCTestCase {

    // MARK: - Model

    func testMemberwiseInitDefaultsToAbsent() {
        let tx = EVMQuote.Transaction(from: "0xFrom", to: "0xTo", data: "0x", value: "0", gasPrice: "1", gas: 1)
        XCTAssertNil(tx.swapFee)
        XCTAssertEqual(tx.swapFeeTokenContract, "")
    }

    func testJSONWithoutSwapFeeDecodesToAbsent() throws {
        let quote = try decodeQuote(txJSON: baseTxJSON)
        XCTAssertNil(quote.tx.swapFee)
    }

    func testJSONWithZeroSwapFeeDecodesToStatedZero() throws {
        let quote = try decodeQuote(txJSON: baseTxJSON + #", "swapFee": "0""#)
        XCTAssertEqual(quote.tx.swapFee, "0")
    }

    func testJSONRoundTripKeepsAbsentAbsent() throws {
        let quote = EVMQuote(
            dstAmount: "1",
            tx: EVMQuote.Transaction(from: "0xFrom", to: "0xTo", data: "0x", value: "0", gasPrice: "1", gas: 1)
        )
        let data = try JSONEncoder().encode(quote)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("swapFee\""), "nil must be omitted, not encoded as null or \"0\"")
        XCTAssertNil(try JSONDecoder().decode(EVMQuote.self, from: data).tx.swapFee)
    }

    // MARK: - Readers

    func testEvmSwapFeeBigIntDistinguishesStatedZeroFromAbsent() {
        XCTAssertEqual(SwapQuote.kyberswap(makeQuote(swapFee: "0"), fee: nil).evmSwapFeeBigInt, 0)
        XCTAssertNil(SwapQuote.kyberswap(makeQuote(swapFee: nil), fee: nil).evmSwapFeeBigInt)
        XCTAssertEqual(SwapQuote.oneinch(makeQuote(swapFee: "5000000"), fee: nil).evmSwapFeeBigInt, 5_000_000)
        XCTAssertNil(SwapQuote.lifi(makeQuote(swapFee: "-1"), fee: nil, integratorFee: nil).evmSwapFeeBigInt)
        XCTAssertNil(SwapQuote.lifi(makeQuote(swapFee: "abc"), fee: nil, integratorFee: nil).evmSwapFeeBigInt)
    }

    // MARK: - LiFi EVM: what a missing fixed-fee entry means

    func testLiFiMissingFixedFeeIsStatedZeroOnlyWhenNoneWasRequested() {
        XCTAssertEqual(LiFiService.extractSwapFee(from: makeLiFiResponse(feeCosts: nil), integratorFee: 0).fee, "0")
        XCTAssertNil(LiFiService.extractSwapFee(from: makeLiFiResponse(feeCosts: []), integratorFee: Decimal(5) / 1000).fee)
        XCTAssertNil(LiFiService.extractSwapFee(from: makeLiFiResponse(feeCosts: nil), integratorFee: nil).fee)
    }

    func testLiFiFixedFeeEntryIsStatedVerbatim() {
        let response = makeLiFiResponse(feeCosts: [
            .init(name: "LIFI Fixed Fee", amount: "250000", included: true, token: .init(address: usdcContract))
        ])
        let extracted = LiFiService.extractSwapFee(from: response, integratorFee: Decimal(5) / 1000)
        XCTAssertEqual(extracted.fee, "250000")
        XCTAssertEqual(extracted.tokenContract, usdcContract)
    }

    // MARK: - Fixtures

    private let usdcContract = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"

    private let baseTxJSON = #""from": "0xFrom", "to": "0xTo", "data": "0x", "value": "0", "gasPrice": "1", "gas": 100000"#

    private func decodeQuote(txJSON: String) throws -> EVMQuote {
        let json = #"{"dstAmount": "3000000000", "tx": {"# + txJSON + "}}"
        return try JSONDecoder().decode(EVMQuote.self, from: Data(json.utf8))
    }

    private func makeQuote(swapFee: String?) -> EVMQuote {
        EVMQuote(
            dstAmount: "3000000000",
            tx: EVMQuote.Transaction(
                from: "0xFrom", to: "0xRouter", data: "0x", value: "0", gasPrice: "1", gas: 100_000,
                swapFee: swapFee, swapFeeTokenContract: usdcContract
            )
        )
    }

    private func makeLiFiResponse(feeCosts: [LifiQuoteResponse.Estimate.FeeCost]?) -> LifiQuoteResponse.EvmQuoteResponse {
        .init(
            estimate: .init(
                toAmount: "3000000000",
                toAmountMin: "2990000000",
                executionDuration: 30,
                gasCosts: [],
                feeCosts: feeCosts
            ),
            transactionRequest: .init(
                data: "0x", to: "0xRouter", value: "0x0", from: "0xFrom", chainId: 1, gasLimit: "0x186a0", gasPrice: "0x1"
            )
        )
    }
}
