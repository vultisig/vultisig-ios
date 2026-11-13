//
//  SwapKitZcashTests.swift
//  VultisigAppTests
//
//  ZEC source via SwapKit: NU5 v5 (ZIP-225) transparent PSBT signed with
//  ZIP-244 sighashes through `ZcashSigner`. Fixture
//  `v3-real-zec-v5-swap` is a real SwapKit `/swap` response (ZEC.ZEC → ETH.ETH,
//  Maya route, deposit + OP_RETURN memo + change). Expected sighash and txid
//  come from an independent Python ZIP-244 implementation run over the same
//  bytes with the input rebound to the golden key (`goldenOwnedFixture`).
//
//  Refused before any keysign: Sapling v4, shielded bundles, non-P2PKH
//  inputs, inputs the vault doesn't own, and a branch id that is missing or
//  differs from the live one.
//

import BigInt
import Foundation
import WalletCore
import XCTest
@testable import VultisigApp

@MainActor
final class SwapKitZcashTests: XCTestCase {

    /// The fixture's consensus branch id (raw LE bytes), standing in for the live one.
    private let testBranchID = "d90a1977"

    // MARK: - v5 body parser

    func testParserAcceptsV5() throws {
        let parsed = try SwapKitZcashSigner.parseUnsignedTx(try unsignedTx(fixture: "v3-real-zec-v5-swap"))
        XCTAssertEqual(parsed.version, 0x80000005)
        XCTAssertEqual(parsed.versionGroupID, 0x26A7270A)
        XCTAssertEqual(parsed.branchID.hexString, testBranchID)
        XCTAssertEqual(parsed.expiryHeight, 0)
        XCTAssertEqual(parsed.inputs.count, 1)
        XCTAssertEqual(parsed.outputs.count, 3, "deposit + OP_RETURN memo + change")
        XCTAssertEqual(parsed.outputs[0].amount, 100_000)
    }

    func testParserRefusesSaplingV4() throws {
        let body = try unsignedTx(fixture: "v3-real-zec-swap")
        XCTAssertThrowsError(try SwapKitZcashSigner.parseUnsignedTx(body)) { err in
            guard case SwapKitZcashSignerError.unsupportedZcashVersion(let v, let g) = err else {
                return XCTFail("expected .unsupportedZcashVersion, got \(err)")
            }
            XCTAssertEqual(v, 0x80000004)
            XCTAssertEqual(g, 0x892F2085)
        }
    }

    func testParserRefusesShieldedBundle() throws {
        var body = try unsignedTx(fixture: "v3-real-zec-v5-swap")
        body[body.count - 3] = 0x01  // one Sapling spend
        XCTAssertThrowsError(try SwapKitZcashSigner.parseUnsignedTx(body)) { err in
            guard case SwapKitZcashSignerError.unsupportedShieldedTransaction = err else {
                return XCTFail("expected .unsupportedShieldedTransaction, got \(err)")
            }
        }
    }

    func testParserRefusesTrailingBytes() throws {
        var body = try unsignedTx(fixture: "v3-real-zec-v5-swap")
        body.append(0x00)
        XCTAssertThrowsError(try SwapKitZcashSigner.parseUnsignedTx(body)) { err in
            guard case SwapKitZcashSignerError.unsupportedShieldedTransaction = err else {
                return XCTFail("expected .unsupportedShieldedTransaction, got \(err)")
            }
        }
    }

    // MARK: - Signer

    func testSighashMatchesIndependentZIP244Reference() throws {
        let hashes = try SwapKitZcashSigner.preSigningHashes(
            payload: try ownedPayload(),
            zcashBranchId: testBranchID,
            pubKeyHex: SwapKitVaultOwnedPSBT.goldenPubKeyHex
        )
        XCTAssertEqual(hashes, ["c5b43b0a5497473f5649361d45111ad815ba951b1fec5946ae2ea5c907139ab3"])
    }

    func testSignedTransactionIsV5WithZIP244TxidAndUntouchedOutputs() throws {
        let payload = try ownedPayload()
        let hashes = try SwapKitZcashSigner.preSigningHashes(
            payload: payload,
            zcashBranchId: testBranchID,
            pubKeyHex: SwapKitVaultOwnedPSBT.goldenPubKeyHex
        )
        let signed = try SwapKitZcashSigner.compileSignedTransaction(
            payload: payload,
            signatures: try SigningGoldenSigner.signatures(forImageHashes: hashes, curve: .secp256k1),
            pubKeyHex: SwapKitVaultOwnedPSBT.goldenPubKeyHex,
            zcashBranchId: testBranchID
        )
        XCTAssertEqual(signed.transactionHash, "46af32ccd24138fb5d51a1790e899f90aff72451785d19b262fb2abfaffd7292")
        let raw = try XCTUnwrap(Data(hexString: signed.rawTransaction))
        XCTAssertEqual(raw.prefix(12).hexString, "050000800a27a726d90a1977", "v5 header, group, branch")
        // Outputs (deposit, OP_RETURN memo, change) are SwapKit's, byte for byte and in order.
        let unsigned = try unsignedTx(fixture: "v3-real-zec-v5-swap")
        let outputs = unsigned.suffix(from: 20 + 1 + 41 + 1).dropLast(3)
        let rebound = SwapKitVaultOwnedPSBT.replacing(
            script: Data(hexString: "76a9147b187e37a86ebb966feb9e83b2fd489e1601b71788ac")!,
            with: SwapKitVaultOwnedPSBT.goldenP2PKHScript,
            in: Data(outputs)
        )
        XCTAssertNotNil(raw.range(of: rebound))
    }

    func testPreSigningHashesRefuseInputsThisVaultDoesNotOwn() throws {
        XCTAssertThrowsError(try SwapKitZcashSigner.preSigningHashes(
            payload: try makePayload(),
            zcashBranchId: testBranchID,
            pubKeyHex: SwapKitVaultOwnedPSBT.goldenPubKeyHex
        )) { err in
            guard case SwapKitZcashSignerError.underlying(.pubkeyDoesNotMatchInput(let index)) = err else {
                return XCTFail("expected .pubkeyDoesNotMatchInput, got \(err)")
            }
            XCTAssertEqual(index, 0)
        }
    }

    func testCompileRefusesInputsThisVaultDoesNotOwn() throws {
        XCTAssertThrowsError(try SwapKitZcashSigner.compileSignedTransaction(
            payload: try makePayload(),
            signatures: [:],
            pubKeyHex: SwapKitVaultOwnedPSBT.goldenPubKeyHex,
            zcashBranchId: testBranchID
        )) { err in
            guard case SwapKitZcashSignerError.underlying(.pubkeyDoesNotMatchInput) = err else {
                return XCTFail("expected .pubkeyDoesNotMatchInput, got \(err)")
            }
        }
    }

    func testSignerRefusesSaplingV4PSBT() throws {
        XCTAssertThrowsError(try SwapKitZcashSigner.preSigningHashes(
            payload: try makePayload(fixture: "v3-real-zec-swap"),
            zcashBranchId: testBranchID,
            pubKeyHex: SwapKitVaultOwnedPSBT.goldenPubKeyHex
        )) { err in
            guard case SwapKitZcashSignerError.unsupportedZcashVersion = err else {
                return XCTFail("expected .unsupportedZcashVersion, got \(err)")
            }
        }
    }

    func testSignerRefusesMissingBranchID() throws {
        XCTAssertThrowsError(try SwapKitZcashSigner.parsePSBT(try makePayload().txPayload, zcashBranchId: nil)) { err in
            guard case SwapKitZcashSignerError.underlying(let inner) = err else {
                return XCTFail("expected underlying plan error, got \(err)")
            }
            XCTAssertTrue(inner.errorDescription?.contains("branch id is unavailable") ?? false)
        }
    }

    func testSignerRefusesBranchIDThatDiffersFromLive() throws {
        XCTAssertThrowsError(try SwapKitZcashSigner.parsePSBT(try makePayload().txPayload, zcashBranchId: "30f33754")) { err in
            guard case SwapKitZcashSignerError.underlying(let inner) = err else {
                return XCTFail("expected underlying plan error, got \(err)")
            }
            XCTAssertTrue(inner.errorDescription?.contains("differs from the live branch id") ?? false)
        }
    }

    func testParsedPSBTKeepsSwapKitOutputsVerbatimAndInOrder() throws {
        let parsed = try SwapKitZcashSigner.parsePSBT(try makePayload().txPayload, zcashBranchId: testBranchID)
        XCTAssertEqual(parsed.outputs.map(\.value), [100_000, 0, 196_432])
        XCTAssertEqual(parsed.outputs[0].customScriptPubkey.hexString, "76a9147b1670a888fc6a8437917bbff3b7f9c64091efce88ac")
        XCTAssertEqual(parsed.outputs[1].customScriptPubkey.first, 0x6a, "OP_RETURN memo stays second")
        XCTAssertEqual(parsed.outputs[2].customScriptPubkey.hexString, "76a9147b187e37a86ebb966feb9e83b2fd489e1601b71788ac")
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

    private func unsignedTx(fixture: String) throws -> Data {
        let bytes = try makePayload(fixture: fixture).txPayload
        return try SwapKitPSBTParser.parseFraming(psbtBytes: bytes).unsignedTxBytes
    }

    private func makePayload(fixture: String = "v3-real-zec-v5-swap") throws -> SwapKitSwapPayload {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: fixture
        )
        guard case let .zcashPsbt(base64) = response.tx else {
            throw NSError(domain: "test", code: 0)
        }
        let bytes = try XCTUnwrap(Data(base64Encoded: base64))
        return SwapKitSwapPayload(
            fromCoin: makeZcashCoin(),
            toCoin: makeUsdcCoin(),
            fromAmount: BigInt(100_000),
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

    /// The captured PSBT with its P2PKH input (and the change output paying back to it)
    /// rebound to the golden key.
    private func ownedPayload() throws -> SwapKitSwapPayload {
        let base = try makePayload()
        return SwapKitSwapPayload(
            fromCoin: base.fromCoin,
            toCoin: base.toCoin,
            fromAmount: base.fromAmount,
            toAmountDecimal: base.toAmountDecimal,
            txType: base.txType,
            txPayload: SwapKitVaultOwnedPSBT.replacing(
                script: Data(hexString: "76a9147b187e37a86ebb966feb9e83b2fd489e1601b71788ac")!,
                with: SwapKitVaultOwnedPSBT.goldenP2PKHScript,
                in: base.txPayload
            ),
            targetAddress: base.targetAddress,
            inboundAddress: base.inboundAddress,
            memo: base.memo,
            subProvider: base.subProvider,
            swapID: base.swapID
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
