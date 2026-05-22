//
//  SwapKitZcashTests.swift
//  VultisigAppTests
//
//  ZEC source via SwapKit NEAR-Intents: Sapling-v4 transparent PSBT signed
//  through WalletCore's `CoinType.zcash` with the branchID required by
//  ZIP-243. Fixture body is the byte-level structure documented in the ZEC
//  source plan §"PSBT byte-level structure" (real probe against
//  `t1bnxtY7aLCjWx9Ru1YcGwRWch3eEWUFK7u`).
//
//  Sapling header parser asserts:
//    - `version == 0x80000004` (overwinter + v4) — rejects v5 (NU5)
//    - `nVersionGroupId == 0x892F2085` (Sapling)
//    - All shielded fields zero — rejects any shielded-bundle transaction
//
//  Hard rejects ride a localized error (`swapKitErrorUnsupportedZcashVersion`,
//  `swapKitErrorUnsupportedShieldedTransaction`) so users see "we can't
//  sign this" rather than a cryptic WalletCore error string.
//

import BigInt
import Foundation
import WalletCore
import XCTest
@testable import VultisigApp

@MainActor
final class SwapKitZcashTests: XCTestCase {

    // MARK: - Decoder

    func testZcashSwapFixtureDecodesAsZcashPsbt() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-zec-swap"
        )
        XCTAssertEqual(response.meta.txType, "PSBT")
        XCTAssertEqual(response.providers, ["NEAR"])
        guard case let .zcashPsbt(base64) = response.tx else {
            return XCTFail("expected .zcashPsbt, got \(response.tx)")
        }
        XCTAssertTrue(base64.hasPrefix("cHNidP8B"))
        XCTAssertTrue(response.targetAddress.hasPrefix("t1"),
                      "ZEC target address must be transparent (`t1…`)")
        XCTAssertEqual(response.inboundAddress, response.targetAddress)
    }

    // MARK: - Payload builder

    func testZcashPayloadBuilderProducesPSBTZECTxType() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-zec-swap"
        )
        guard case let .zcashPsbt(base64) = response.tx else {
            return XCTFail("expected .zcashPsbt")
        }
        let payload = try SwapCryptoLogic.buildSwapKitLegacyPSBTPayload(
            fromCoin: makeZcashCoin(),
            toCoin: makeUsdcCoin(),
            fromAmountInCoin: BigInt(100_000_000),
            toAmountDecimal: Decimal(string: "655.026517") ?? 0,
            base64PSBT: base64,
            txType: "PSBT_ZEC",
            swapResponse: response
        )
        XCTAssertEqual(payload.txType, "PSBT_ZEC")
        XCTAssertEqual(payload.targetAddress, response.targetAddress)
        XCTAssertEqual(payload.txPayload.base64EncodedString(), base64)
    }

    // MARK: - Sapling header parser

    func testSaplingHeaderParserAcceptsV4() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-zec-swap"
        )
        guard case let .zcashPsbt(base64) = response.tx else {
            return XCTFail("expected .zcashPsbt")
        }
        let psbtBytes = try XCTUnwrap(Data(base64Encoded: base64))
        // The unsigned-tx body lives at the value of global key 0x00. We
        // re-extract it through SwapKitPSBTParser for the test.
        let framing = try SwapKitPSBTParser.parseFraming(psbtBytes: psbtBytes)
        let parsed = try SwapKitZcashSigner.parseSaplingUnsignedTx(framing.unsignedTxBytes)
        XCTAssertEqual(parsed.version, 0x80000004, "Sapling v4 with overwinter bit")
        XCTAssertEqual(parsed.versionGroupID, 0x892F2085, "Sapling consensus group ID")
        XCTAssertEqual(parsed.inputs.count, 1)
        XCTAssertEqual(parsed.outputs.count, 2)
        XCTAssertEqual(parsed.outputs[0].amount, 100_000_000, "Deposit output: 1 ZEC")
    }

    func testSaplingHeaderParserRejectsV5() {
        // Hand-mutate the version field of the unsigned-tx body to 0x80000005
        // (overwinter + v5 = NU5). Parser must throw `unsupportedZcashVersion`.
        var body = Data()
        body.append(contentsOf: [0x05, 0x00, 0x00, 0x80])  // version = 0x80000005
        body.append(contentsOf: [0x85, 0x20, 0x2f, 0x89])  // group ID unchanged
        // ...rest doesn't matter; parser stops at version+group check.
        XCTAssertThrowsError(try SwapKitZcashSigner.parseSaplingUnsignedTx(body)) { err in
            guard case SwapKitZcashSignerError.unsupportedZcashVersion(let v, let g) = err else {
                return XCTFail("expected .unsupportedZcashVersion, got \(err)")
            }
            XCTAssertEqual(v, 0x80000005)
            XCTAssertEqual(g, 0x892F2085)
        }
    }

    func testSaplingHeaderParserRejectsNu5VersionGroup() {
        var body = Data()
        body.append(contentsOf: [0x04, 0x00, 0x00, 0x80])  // version = v4 (good)
        body.append(contentsOf: [0x0a, 0x27, 0xa7, 0x26])  // group ID = 0x26A7270A (NU5 — bad)
        XCTAssertThrowsError(try SwapKitZcashSigner.parseSaplingUnsignedTx(body)) { err in
            guard case SwapKitZcashSignerError.unsupportedZcashVersion = err else {
                return XCTFail("expected .unsupportedZcashVersion, got \(err)")
            }
        }
    }

    // MARK: - Signer structural coverage

    func testZcashSignerProducesOneHashPerInput() throws {
        let payload = try makePayload()
        let hashes = try SwapKitZcashSigner.preSigningHashes(payload: payload)
        XCTAssertEqual(hashes.count, 1, "Fixture has 1 input → 1 preimage hash")
        for hash in hashes {
            XCTAssertEqual(hash.count, 64)
        }
    }

    func testZcashSignerBuildsBitcoinSigningInputWithSaplingBranchID() throws {
        let payload = try makePayload()
        let input = try SwapKitZcashSigner.buildSigningInput(payload: payload)
        XCTAssertEqual(input.coinType, CoinType.zcash.rawValue)
        XCTAssertEqual(input.utxo.count, 1)
        XCTAssertEqual(input.plan.utxos.count, 1)
        // BranchID matches the existing native ZEC send path
        // (`UTXOChainsHelper.swift:138-139`). Diverging would produce a
        // digest the network rejects.
        XCTAssertEqual(input.plan.branchID.hexString, "f04dec4d")
    }

    // MARK: - EVM builder defence-in-depth

    func testEvmBuilderRejectsZcashPsbt() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-zec-swap"
        )
        XCTAssertThrowsError(try SwapCryptoLogic.buildEVMQuoteFromSwapKit(swapResponse: response)) { err in
            guard case SwapKitError.unsupportedTxType(let txType) = err else {
                return XCTFail("expected unsupportedTxType, got \(err)")
            }
            XCTAssertEqual(txType, "PSBT_ZEC")
        }
    }

    // MARK: - Helpers

    private func makePayload() throws -> SwapKitSwapPayload {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-zec-swap"
        )
        guard case let .zcashPsbt(base64) = response.tx else {
            throw NSError(domain: "test", code: 0)
        }
        let bytes = try XCTUnwrap(Data(base64Encoded: base64))
        return SwapKitSwapPayload(
            fromCoin: makeZcashCoin(),
            toCoin: makeUsdcCoin(),
            fromAmount: BigInt(100_000_000),
            toAmountDecimal: 0,
            txType: "PSBT_ZEC",
            txPayload: bytes,
            targetAddress: response.targetAddress,
            inboundAddress: response.inboundAddress,
            memo: nil,
            subProvider: response.subProvider,
            swapID: response.swapId
        )
    }

    private func makeZcashCoin() -> Coin {
        let meta = CoinMeta.make(chain: .zcash, ticker: "ZEC", decimals: 8, isNativeToken: true)
        return Coin(asset: meta, address: "t1bnxtY7aLCjWx9Ru1YcGwRWch3eEWUFK7u", hexPublicKey: "")
    }

    private func makeUsdcCoin() -> Coin {
        let meta = CoinMeta.make(chain: .ethereum, ticker: "USDC", decimals: 6, isNativeToken: false)
        return Coin(asset: meta, address: "0xtest", hexPublicKey: "")
    }
}
