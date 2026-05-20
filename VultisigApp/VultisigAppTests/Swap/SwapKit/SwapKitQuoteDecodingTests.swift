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

    func testTronSwapResponseDecodesAsUnsupported() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-tron-final-swap-fresh"
        )
        XCTAssertEqual(response.meta.txType, "TRON")
        guard case let .unsupported(txType, _) = response.tx else {
            XCTFail("Expected unsupported tx variant for Phase 1")
            return
        }
        XCTAssertEqual(txType, "TRON")
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
