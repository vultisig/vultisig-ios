//
//  ThorchainSwapQuoteRequestTests.swift
//  VultisigAppTests
//
//  Pins the on-wire slippage contract for THORChain / Maya swap quotes: the
//  request must carry `liquidity_tolerance_bps` (movement-anchored, immune to
//  price impact) and must NEVER carry `tolerance_bps` (feeless-anchored, gated
//  against the single-swap emit — it rejects any swap with real price impact,
//  which is why it was shipped and reverted once). Omitted when nil, so an
//  explicit 0-bps selection sends no floor.
//

@testable import VultisigApp
import XCTest

final class ThorchainSwapQuoteRequestTests: XCTestCase {

    private enum TaskShapeError: Error { case notRequestParameters }

    private func params(from task: HTTPTask) throws -> [String: Any] {
        guard case let .requestParameters(params, _) = task else {
            XCTFail("swapQuote must build requestParameters")
            throw TaskShapeError.notRequestParameters
        }
        return params
    }

    private func mainnetSwapQuoteParams(liquidityToleranceBps: String?) throws -> [String: Any] {
        try params(from: ThorchainMainnetAPI(.swapQuote(
            fromAsset: "BTC.BTC",
            toAsset: "ETH.ETH",
            amount: "10000000",
            destination: "0x742d35Cc6634C0532925a3b844Bc454e4438f44e",
            streamingInterval: "0",
            streamingQuantity: nil,
            affiliates: "vi",
            affiliateBps: "50",
            liquidityToleranceBps: liquidityToleranceBps
        )).task)
    }

    private func mayaSwapQuoteParams(liquidityToleranceBps: String?) throws -> [String: Any] {
        try params(from: MayaChainAPI(.swapQuote(
            fromAsset: "BTC.BTC",
            toAsset: "ETH.ETH",
            amount: "10000000",
            destination: "0x742d35Cc6634C0532925a3b844Bc454e4438f44e",
            streamingInterval: "3",
            streamingQuantity: nil,
            affiliate: "vi",
            affiliateBps: "50",
            liquidityToleranceBps: liquidityToleranceBps
        )).task)
    }

    // MARK: - THORChain mainnet

    func testMainnetSwapQuoteSendsLiquidityToleranceBps() throws {
        let params = try mainnetSwapQuoteParams(liquidityToleranceBps: "100")
        XCTAssertEqual(params["liquidity_tolerance_bps"] as? String, "100")
    }

    func testMainnetSwapQuoteOmitsToleranceWhenNil() throws {
        let params = try mainnetSwapQuoteParams(liquidityToleranceBps: nil)
        XCTAssertNil(params["liquidity_tolerance_bps"],
                     "nil (Auto→0, or explicit 0 bps) must omit the floor param, not send it")
    }

    func testMainnetSwapQuoteNeverSendsLegacyToleranceBps() throws {
        // The regression this guards: reverting to `tolerance_bps` (the param
        // that rejects price-impacted swaps) must fail loudly here.
        let values: [String?] = ["100", nil]
        for value in values {
            let params = try mainnetSwapQuoteParams(liquidityToleranceBps: value)
            XCTAssertNil(params["tolerance_bps"],
                         "legacy `tolerance_bps` must never be on the wire (value=\(value ?? "nil"))")
        }
    }

    // MARK: - Maya

    func testMayaSwapQuoteSendsLiquidityToleranceBpsAndNeverLegacy() throws {
        let params = try mayaSwapQuoteParams(liquidityToleranceBps: "100")
        XCTAssertEqual(params["liquidity_tolerance_bps"] as? String, "100")
        XCTAssertNil(params["tolerance_bps"], "Maya must not send legacy `tolerance_bps` either")
    }

    func testMayaSwapQuoteOmitsToleranceWhenNil() throws {
        let params = try mayaSwapQuoteParams(liquidityToleranceBps: nil)
        XCTAssertNil(params["liquidity_tolerance_bps"])
        XCTAssertNil(params["tolerance_bps"])
    }
}
