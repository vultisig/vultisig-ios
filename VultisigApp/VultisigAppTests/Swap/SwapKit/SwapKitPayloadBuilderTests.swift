//
//  SwapKitPayloadBuilderTests.swift
//  VultisigAppTests
//
//  Structural coverage for the `.swapkit` branch in
//  `SwapCryptoLogic.buildEVMQuoteFromSwapKit` and the surrounding payload
//  dispatcher. Asserts the EVM↔EVMQuote mirror, Solana base64 passthrough,
//  and the descriptive error for `txType` values Phase 1 doesn't yet
//  support.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SwapKitPayloadBuilderTests: XCTestCase {

    func testEvmSwapResponseProducesMirroredEVMQuote() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-erc20-erc20-swap"
        )
        let quote = try SwapCryptoLogic.buildEVMQuoteFromSwapKit(swapResponse: response)
        XCTAssertEqual(quote.tx.to, "0x9025B8ff35Ca44f7018C3a37FE0f69e63DBb0743")
        XCTAssertEqual(quote.tx.from, "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045")
        XCTAssertTrue(quote.tx.data.hasPrefix("0xda5d4170"))
        XCTAssertNotEqual(quote.tx.gas, 0, "gas should be normalised from SwapKit's hex value")
    }

    func testSolanaSwapResponseStashesBase64IntoEVMQuoteData() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-sol-near-swap-fresh"
        )
        let quote = try SwapCryptoLogic.buildEVMQuoteFromSwapKit(swapResponse: response)
        XCTAssertEqual(quote.tx.to, response.targetAddress)
        XCTAssertEqual(quote.tx.from, response.sourceAddress)
        XCTAssertEqual(quote.tx.value, "0")
        XCTAssertNotNil(Data(base64Encoded: quote.tx.data))
    }

    func testTronSwapResponseThrowsUnsupportedTxType() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-tron-final-swap-fresh"
        )
        XCTAssertThrowsError(try SwapCryptoLogic.buildEVMQuoteFromSwapKit(swapResponse: response)) { error in
            guard case SwapKitError.unsupportedTxType(let txType) = error else {
                XCTFail("Expected unsupportedTxType, got \(error)")
                return
            }
            XCTAssertEqual(txType, "TRON")
        }
    }

    func testApprovePayloadUsesMetaApprovalAddressWhenPresent() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-erc20-erc20-swap"
        )
        let usdt = makeCoin(.ethereum, ticker: "USDT", decimals: 6, isNative: false)
        let payload = SwapCryptoLogic.buildSwapKitApprovePayload(
            fromCoin: usdt,
            amount: BigInt(100_000_000),
            swapResponse: response,
            fallback: nil
        )
        XCTAssertEqual(
            payload?.spender,
            "0x6C0AD82f9721A6dc986381d19338601a2E6370e5",
            "spender must come from meta.approvalAddress when populated"
        )
    }

    func testApprovePayloadFallsBackForNativeSource() throws {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let response = try makeMinimalEvmResponse()
        let payload = SwapCryptoLogic.buildSwapKitApprovePayload(
            fromCoin: eth,
            amount: BigInt(1),
            swapResponse: response,
            fallback: nil
        )
        XCTAssertNil(payload, "Native source never needs approval")
    }

    // MARK: - Fixtures

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        return Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
    }

    private func makeMinimalEvmResponse() throws -> SwapKitSwapResponse {
        // Synthesise a minimal EVM-flavoured response by re-encoding a tiny
        // JSON literal. Keeps the test independent of the network fixtures.
        let json = """
        {
          "swapId": "x",
          "routeId": "r",
          "providers": ["ONEINCH"],
          "sellAsset": "ETH.ETH",
          "buyAsset": "ETH.USDC",
          "sellAmount": "0.01",
          "expectedBuyAmount": "21.0",
          "expectedBuyAmountMaxSlippage": "20.9",
          "sourceAddress": "0xFrom",
          "destinationAddress": "0xTo",
          "targetAddress": "0xRouter",
          "inboundAddress": null,
          "fees": [],
          "warnings": [],
          "meta": {"txType": "EVM"},
          "tx": {"to":"0xRouter","from":"0xFrom","value":"0","data":"0x","gas":"0x0","gasPrice":"0x0"},
          "approvalTx": null
        }
        """
        return try JSONDecoder().decode(SwapKitSwapResponse.self, from: Data(json.utf8))
    }
}
