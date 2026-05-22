//
//  SwapKitBitcoinCashTests.swift
//  VultisigAppTests
//
//  BCH source via SwapKit NEAR-Intents: legacy P2PKH PSBT signed through
//  WalletCore's `CoinType.bitcoinCash`. Mirrors `SwapKitDogeTests` — same
//  shared `SwapKitLegacyP2PKHSigner` helper, different `CoinType` (BCH
//  picks up SIGHASH_FORKID via `BitcoinScript.hashTypeForCoin`).
//
//  Every `/v3/swap` probe against BCH during the spike returned
//  `failedToRetrieveBalance`, so this fixture is hand-crafted from the
//  strong DOGE analogue (same PSBT shape, NON_WITNESS_UTXO with embedded
//  prev-tx). When SwapKit's BCH balance indexer recovers we vendor the
//  real wire body — but the structural assertions below already pin every
//  layer the runtime needs.
//

import BigInt
import Foundation
import WalletCore
import XCTest
@testable import VultisigApp

@MainActor
final class SwapKitBitcoinCashTests: XCTestCase {

    // MARK: - Decoder

    func testBchSwapFixtureDecodesAsBitcoinCashPsbt() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-bch-swap"
        )
        XCTAssertEqual(response.meta.txType, "PSBT")
        XCTAssertEqual(response.providers, ["NEAR"])
        guard case let .bitcoinCashPsbt(base64) = response.tx else {
            return XCTFail("expected .bitcoinCashPsbt, got \(response.tx)")
        }
        XCTAssertTrue(base64.hasPrefix("cHNidP8B"),
                      "PSBT must start with `psbt\\xff` magic bytes")
        XCTAssertNotNil(Data(base64Encoded: base64), "tx must be valid base64")
    }

    // MARK: - Payload builder

    func testBchPayloadBuilderProducesPSBTBCHTxType() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-bch-swap"
        )
        guard case let .bitcoinCashPsbt(base64) = response.tx else {
            return XCTFail("expected .bitcoinCashPsbt")
        }
        let payload = try SwapCryptoLogic.buildSwapKitLegacyPSBTPayload(
            fromCoin: makeBchCoin(),
            toCoin: makeUsdcCoin(),
            fromAmountInCoin: BigInt(50_000_000), // 0.5 BCH × 1e8
            toAmountDecimal: Decimal(string: "187.857415") ?? 0,
            base64PSBT: base64,
            txType: "PSBT_BCH",
            swapResponse: response
        )
        XCTAssertEqual(payload.txType, "PSBT_BCH")
        XCTAssertEqual(payload.targetAddress, response.targetAddress)
        XCTAssertEqual(payload.txPayload.base64EncodedString(), base64,
                       "tx_payload bytes must round-trip back to the original PSBT")
    }

    // MARK: - Signer structural coverage

    func testBchSignerProducesOneHashPerInput() throws {
        let payload = try makePayload()
        let hashes = try SwapKitBCHSigner.preSigningHashes(payload: payload)
        XCTAssertEqual(hashes.count, 1, "Fixture has 1 input → 1 preimage hash")
        for hash in hashes {
            XCTAssertEqual(hash.count, 64)
            XCTAssertEqual(hash, hash.lowercased())
        }
    }

    func testBchSignerBuildsBitcoinSigningInputWithBCHCoinType() throws {
        let payload = try makePayload()
        let input = try SwapKitBCHSigner.buildSigningInput(payload: payload)
        XCTAssertEqual(input.coinType, CoinType.bitcoinCash.rawValue)
        XCTAssertEqual(input.utxo.count, 1)
        XCTAssertEqual(input.plan.utxos.count, 1)
        XCTAssertGreaterThan(input.plan.amount, 0)
        // BCH's hash-type byte sets SIGHASH_FORKID (`0x40`) alongside
        // SIGHASH_ALL (`0x01`) → `0x41`. WalletCore picks this up via
        // `BitcoinScript.hashTypeForCoin(.bitcoinCash)`.
        XCTAssertEqual(
            input.hashType,
            BitcoinScript.hashTypeForCoin(coinType: .bitcoinCash),
            "BCH hash type must include SIGHASH_FORKID"
        )
    }

    func testBchSignerRejectsEmptyPayload() {
        let empty = SwapKitSwapPayload(
            fromCoin: makeBchCoin(),
            toCoin: makeUsdcCoin(),
            fromAmount: 0,
            toAmountDecimal: 0,
            txType: "PSBT_BCH",
            txPayload: Data(),
            targetAddress: "",
            inboundAddress: nil,
            memo: nil,
            subProvider: "NEAR",
            swapID: "test"
        )
        XCTAssertThrowsError(try SwapKitBCHSigner.preSigningHashes(payload: empty)) { err in
            guard case SwapKitBCHSignerError.underlying(let inner) = err else {
                return XCTFail("expected wrapped error, got \(err)")
            }
            guard case .missingPSBT = inner else {
                return XCTFail("expected .missingPSBT, got \(inner)")
            }
        }
    }

    // MARK: - EVM builder defence-in-depth

    func testEvmBuilderRejectsBchPsbt() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-bch-swap"
        )
        XCTAssertThrowsError(try SwapCryptoLogic.buildEVMQuoteFromSwapKit(swapResponse: response)) { err in
            guard case SwapKitError.unsupportedTxType(let txType) = err else {
                return XCTFail("expected unsupportedTxType, got \(err)")
            }
            XCTAssertEqual(txType, "PSBT_BCH")
        }
    }

    // MARK: - Helpers

    private func makePayload() throws -> SwapKitSwapPayload {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-bch-swap"
        )
        guard case let .bitcoinCashPsbt(base64) = response.tx else {
            throw NSError(domain: "test", code: 0)
        }
        let bytes = try XCTUnwrap(Data(base64Encoded: base64))
        return SwapKitSwapPayload(
            fromCoin: makeBchCoin(),
            toCoin: makeUsdcCoin(),
            fromAmount: BigInt(50_000_000),
            toAmountDecimal: 0,
            txType: "PSBT_BCH",
            txPayload: bytes,
            targetAddress: response.targetAddress,
            inboundAddress: response.inboundAddress,
            memo: nil,
            subProvider: response.subProvider,
            swapID: response.swapId
        )
    }

    private func makeBchCoin() -> Coin {
        let meta = CoinMeta.make(chain: .bitcoinCash, ticker: "BCH", decimals: 8, isNativeToken: true)
        return Coin(asset: meta, address: "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx08", hexPublicKey: "")
    }

    private func makeUsdcCoin() -> Coin {
        let meta = CoinMeta.make(chain: .ethereum, ticker: "USDC", decimals: 6, isNativeToken: false)
        return Coin(asset: meta, address: "0xtest", hexPublicKey: "")
    }
}
