//
//  SwapKitQuoteDecodingTests.swift
//  VultisigAppTests
//
//  Fixture-driven decoder assertions for the SwapKit V3 `/v3/quote` +
//  `/v3/swap` responses. Locks the wire-format shape captured by the Phase 0
//  spike so a future API tweak that breaks the iOS decoder shows up here
//  before it ships.
//

import XCTest
@testable import VultisigApp

final class SwapKitQuoteDecodingTests: XCTestCase {

    func testQuoteFixtureDecodesAllThreeRoutes() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitQuoteResponse.self,
            from: "01b-quote-v3"
        )
        XCTAssertEqual(response.quoteId, "1f909072-2719-4162-b65b-9e080065ab98")
        XCTAssertEqual(response.routes.count, 3)
        XCTAssertEqual(response.routes[0].providers, ["ONEINCH"])
        XCTAssertEqual(response.routes[1].providers, ["NEAR"])
        XCTAssertEqual(response.routes[2].providers, ["CHAINFLIP"])
        XCTAssertEqual(response.routes[0].expectedBuyAmount, "21.165841")
        XCTAssertNil(response.routes[0].meta.txType, "txType is null at quote stage")
    }

    func testEvmSwapResponseDecodesTxAndApprovalTx() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-erc20-erc20-swap"
        )
        XCTAssertEqual(response.meta.txType, "EVM")
        XCTAssertEqual(response.subProvider, "ONEINCH")
        guard case let .evm(tx) = response.tx else {
            XCTFail("Expected EVM tx variant")
            return
        }
        XCTAssertEqual(tx.to, "0x9025B8ff35Ca44f7018C3a37FE0f69e63DBb0743")
        XCTAssertEqual(tx.gas, "0x55730")
        XCTAssertEqual(tx.gasPrice, "0x2aaa0b23")
        XCTAssertEqual(tx.value, "0")
        XCTAssertTrue(tx.data.hasPrefix("0xda5d4170"))

        let approval = try XCTUnwrap(response.approvalTx)
        XCTAssertEqual(approval.to, "0xdAC17F958D2ee523a2206206994597C13D831ec7")
        XCTAssertEqual(approval.gasLimit, "0xbf28", "approvalTx uses `gasLimit`, not `gas`")
        XCTAssertEqual(response.meta.approvalAddress, "0x6C0AD82f9721A6dc986381d19338601a2E6370e5")
    }

    func testSolanaSwapResponseDecodesBase64Tx() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-sol-near-swap-fresh"
        )
        XCTAssertEqual(response.meta.txType, "SOLANA")
        XCTAssertEqual(response.subProvider, "NEAR")
        guard case let .solana(base64) = response.tx else {
            XCTFail("Expected SOLANA tx variant")
            return
        }
        XCTAssertFalse(base64.isEmpty)
        XCTAssertNotNil(Data(base64Encoded: base64), "tx must be a valid base64 payload")
        XCTAssertNil(response.approvalTx, "Solana routes do not produce approvalTx")
        XCTAssertEqual(response.inboundAddress, "2yBEjZS6CC44UwBBGvx8Z1xXHJj4sSD5ZRwba4ijtD7n")
    }

    func testBitcoinSwapResponseDecodesAsPSBT() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-btc-all-swap"
        )
        XCTAssertEqual(response.meta.txType, "PSBT")
        XCTAssertEqual(response.subProvider, "NEAR")
        guard case let .psbt(base64) = response.tx else {
            XCTFail("Expected PSBT tx variant")
            return
        }
        XCTAssertTrue(base64.hasPrefix("cHNidP8B"), "PSBT magic prefix")
        XCTAssertNotNil(Data(base64Encoded: base64))
    }

    /// PSBT shape with an unknown source chain. Phase 1 routed every
    /// unknown PSBT chain into the BTC/LTC segwit signer as a default
    /// fall-through — dangerous because routing a (say) Decred or
    /// Komodo PSBT into the BIP-143 segwit signer would either
    /// silently misdecode or produce an invalid signature. The decoder
    /// now uses an explicit allowlist (BTC/LTC/DOGE/BCH/DASH/ZEC) and
    /// surfaces unknown chains through the typed `.unsupported`
    /// case with `txType: "PSBT/<chain>"` so the keysign dispatcher
    /// throws `unsupportedTxType` rather than silently signing.
    func testUnknownPSBTChainFallsThroughToUnsupported() throws {
        let json = #"""
        {
          "swapId": "00000000-0000-0000-0000-000000000000",
          "routeId": "00000000-0000-0000-0000-000000000000",
          "providers": ["NEAR"],
          "sellAsset": "DCR.DCR",
          "buyAsset": "ETH.USDC-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
          "sellAmount": "1",
          "expectedBuyAmount": "10",
          "expectedBuyAmountMaxSlippage": "9.9",
          "sourceAddress": "DcXyz",
          "destinationAddress": "0x0000000000000000000000000000000000000000",
          "targetAddress": "DcAbc",
          "meta": { "txType": "PSBT" },
          "tx": "cHNidP8BAHcBAAAAAQ==",
          "fees": []
        }
        """#
        let response = try JSONDecoder().decode(SwapKitSwapResponse.self, from: Data(json.utf8))
        guard case .unsupported(let txType, _) = response.tx else {
            return XCTFail("expected .unsupported for unknown PSBT chain, got \(response.tx)")
        }
        XCTAssertEqual(txType, "PSBT/DCR",
                       "Unknown PSBT chain must surface as txType=PSBT/<chain> (no default fall-through to .psbt)")
    }

    /// Synthesizes a fictional unknown `tx_type` to lock the decoder's
    /// fall-through behaviour. TRON used to live here as a Phase 1 sentinel;
    /// Phase 3 promoted it to a typed `.tron` case (see
    /// `SwapKitLongTailTests.testTronSwapResponseDecodesAsTronWebObject`)
    /// so this test now uses a never-shipped chain string to stand in for
    /// "future SwapKit chain we don't yet decode."
    func testUnknownTxTypeFallsThroughToUnsupported() throws {
        let json = #"""
        {
          "swapId": "00000000-0000-0000-0000-000000000000",
          "routeId": "00000000-0000-0000-0000-000000000000",
          "providers": ["FUTURE_PROVIDER"],
          "sellAsset": "FUTURE.TOKEN",
          "buyAsset": "ETH.USDC-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
          "sellAmount": "1",
          "expectedBuyAmount": "1",
          "expectedBuyAmountMaxSlippage": "1",
          "sourceAddress": "future-address",
          "destinationAddress": "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
          "targetAddress": "future-deposit-address",
          "meta": { "txType": "FUTURE_CHAIN" },
          "tx": { "any": "shape" },
          "fees": []
        }
        """#
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(SwapKitSwapResponse.self, from: data)
        XCTAssertEqual(response.meta.txType, "FUTURE_CHAIN")
        guard case let .unsupported(txType, _) = response.tx else {
            return XCTFail("Expected unsupported tx variant for unknown txType")
        }
        XCTAssertEqual(txType, "FUTURE_CHAIN")
    }

    func testProvidersFixtureDecodesEnabledChainIds() throws {
        let providers = try SwapKitFixtureLoader.decode(
            [SwapKitProvider].self,
            from: "02-providers"
        )
        XCTAssertGreaterThan(providers.count, 5)
        let near = try XCTUnwrap(providers.first(where: { $0.name == "NEAR" }))
        XCTAssertTrue(near.enabledChainIds.contains("solana"))
        XCTAssertTrue(near.enabledChainIds.contains("1"))
    }
}
