//
//  SwapKitDashTests.swift
//  VultisigAppTests
//
//  DASH source via SwapKit NEAR-Intents: legacy P2PKH PSBT signed through
//  WalletCore's `CoinType.dash`. Mirrors `SwapKitDogeTests` /
//  `SwapKitBitcoinCashTests` — same shared `SwapKitLegacyP2PKHSigner`
//  helper, different `CoinType`.
//
//  The DASH `/v3/swap` probe during the spike returned
//  `insufficientBalance` (test address empty), so the canonical PSBT body
//  wasn't observed directly. Hand-crafted fixture from the strong DOGE
//  analogue + the DASH plan's documented address pair
//  (`XdAUmwtig27HBG6WfYyHAzP8n6XC9jESEw`).
//

import BigInt
import Foundation
import WalletCore
import XCTest
@testable import VultisigApp

@MainActor
final class SwapKitDashTests: XCTestCase {

    // MARK: - Decoder

    func testDashSwapFixtureDecodesAsDashPsbt() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-dash-swap"
        )
        XCTAssertEqual(response.meta.txType, "PSBT")
        XCTAssertEqual(response.providers, ["NEAR"])
        guard case let .dashPsbt(base64) = response.tx else {
            return XCTFail("expected .dashPsbt, got \(response.tx)")
        }
        XCTAssertTrue(base64.hasPrefix("cHNidP8B"))
        XCTAssertTrue(response.targetAddress.hasPrefix("X"),
                      "DASH legacy address starts with `X`")
    }

    // MARK: - Payload builder

    func testDashPayloadBuilderProducesPSBTDashTxType() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-dash-swap"
        )
        guard case let .dashPsbt(base64) = response.tx else {
            return XCTFail("expected .dashPsbt")
        }
        let payload = try SwapCryptoLogic.buildSwapKitLegacyPSBTPayload(
            fromCoin: makeDashCoin(),
            toCoin: makeUsdcCoin(),
            fromAmountInCoin: BigInt(1_000_000_000),
            toAmountDecimal: Decimal(string: "481.955786") ?? 0,
            base64PSBT: base64,
            txType: "PSBT_DASH",
            swapResponse: response
        )
        XCTAssertEqual(payload.txType, "PSBT_DASH")
        XCTAssertEqual(payload.targetAddress, response.targetAddress)
        XCTAssertEqual(payload.txPayload.base64EncodedString(), base64)
    }

    // MARK: - Signer structural coverage

    func testDashSignerProducesOneHashPerInput() throws {
        let payload = try makePayload()
        let hashes = try SwapKitDashSigner.preSigningHashes(payload: payload)
        XCTAssertEqual(hashes.count, 1)
        // `XCTAssertEqual` is non-fatal, so a count mismatch would
        // continue into `hashes[0]` and crash with an index out-of-range
        // trap rather than reporting the size-vs-element assertion. Use
        // `XCTUnwrap` on `hashes.first` to abort with a clean diagnostic.
        let first = try XCTUnwrap(hashes.first)
        XCTAssertEqual(first.count, 64)
    }

    func testDashSignerBuildsBitcoinSigningInputWithDashCoinType() throws {
        let payload = try makePayload()
        let input = try SwapKitDashSigner.buildSigningInput(payload: payload)
        XCTAssertEqual(input.coinType, CoinType.dash.rawValue)
        XCTAssertEqual(input.utxo.count, 1)
        XCTAssertEqual(input.plan.utxos.count, 1)
        XCTAssertGreaterThan(input.plan.amount, 0)
    }

    // MARK: - EVM builder defence-in-depth

    func testEvmBuilderRejectsDashPsbt() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-dash-swap"
        )
        XCTAssertThrowsError(try SwapCryptoLogic.buildEVMQuoteFromSwapKit(swapResponse: response)) { err in
            guard case SwapKitError.unsupportedTxType(let txType) = err else {
                return XCTFail("expected unsupportedTxType, got \(err)")
            }
            XCTAssertEqual(txType, "PSBT_DASH")
        }
    }

    // MARK: - Helpers

    private func makePayload() throws -> SwapKitSwapPayload {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-dash-swap"
        )
        guard case let .dashPsbt(base64) = response.tx else {
            throw NSError(domain: "test", code: 0)
        }
        let bytes = try XCTUnwrap(Data(base64Encoded: base64))
        return SwapKitSwapPayload(
            fromCoin: makeDashCoin(),
            toCoin: makeUsdcCoin(),
            fromAmount: BigInt(1_000_000_000),
            toAmountDecimal: 0,
            txType: "PSBT_DASH",
            txPayload: bytes,
            targetAddress: response.targetAddress,
            inboundAddress: response.inboundAddress,
            memo: nil,
            subProvider: response.subProvider,
            swapID: response.swapId
        )
    }

    private func makeDashCoin() -> Coin {
        let meta = CoinMeta.make(chain: .dash, ticker: "DASH", decimals: 8, isNativeToken: true)
        return Coin(asset: meta, address: "XdAUmwtig27HBG6WfYyHAzP8n6XC9jESEw", hexPublicKey: "")
    }

    private func makeUsdcCoin() -> Coin {
        let meta = CoinMeta.make(chain: .ethereum, ticker: "USDC", decimals: 6, isNativeToken: false)
        return Coin(asset: meta, address: "0xtest", hexPublicKey: "")
    }
}
