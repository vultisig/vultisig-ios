//
//  SwapKitCardanoSignerTests.swift
//  VultisigAppTests
//
//  Phase 4 follow-on: pre-signing + envelope-assembly coverage for the
//  SwapKit-built Cardano CBOR flow. The Blake2b-256 digest of the embedded
//  transaction body is pinnable from the SwapKit response — if our CBOR
//  walker ever drifts on item-0 boundaries, the digest assertion fires.
//

import BigInt
import Foundation
import XCTest
@testable import VultisigApp

final class SwapKitCardanoSignerTests: XCTestCase {

    /// Real SwapKit `/v3/swap` response body (Cardano source, NEAR-routed).
    /// Single input, two outputs (deposit + change), fee 0x2888d, TTL
    /// 0x0b324cbb. Witness set is empty (`a0`) — that's the slot we fill
    /// after MPC signing.
    private static let unsignedCborHex =
        "84a40081825820f18b3c232d78ca5b1c9e5112314261d839d52a12a5c446c4f80317dc8ac60d48" +
        "000182a200581d618749053dab2309d9b9eba75e17b0406d78302503b4187ca3af260960011a02" +
        "b54eb8a200581d6148838772eed76ee662d3d444e4f8791544e62fa800eb775ec84de62e011a02" +
        "2046f7021a0002888d031a0b324cbba0f5f6"

    // MARK: - Decoder routing

    func testCborTxTypeWithPrebuiltBodyDecodesAsCardanoPrebuilt() throws {
        // SwapKit's live shape: `meta.txType: "CBOR"` + `tx: "<hex>"` →
        // pre-built CBOR flow. The decoder must surface a typed
        // `.cardanoPrebuilt` case with the bytes parsed out — anything else
        // would silently route through the deposit-only path and re-build a
        // transaction with a different tx_id.
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-ada-cbor-prebuilt-swap"
        )
        XCTAssertEqual(response.meta.txType, "CBOR")
        guard case .cardanoPrebuilt(let cbor) = response.tx else {
            return XCTFail("expected .cardanoPrebuilt case, got \(response.tx)")
        }
        // 67-byte body + 1-byte witness + 1-byte is_valid + 1-byte aux_data
        // header + outer array(4) header. 135 bytes total — pin the round-
        // tripped byte count so a fixture truncation surfaces here.
        XCTAssertEqual(cbor.count, 135)
        XCTAssertEqual(cbor.hexString, Self.unsignedCborHex)
    }

    // MARK: - Pre-signing digest

    func testPreSigningHashFromUserCbor() throws {
        let payload = try makePayload()
        let hashes = try SwapKitCardanoSigner.preSigningHashes(payload: payload)
        // Cardano signs a single Blake2b-256 digest of the body, independent
        // of input count.
        XCTAssertEqual(hashes.count, 1)
        // Pinned from the captured SwapKit fixture: Blake2b-256 of the
        // 131-byte CBOR body (item 0 of the envelope). Any drift in the CBOR
        // walker's item-0 boundary detection fires this assertion.
        XCTAssertEqual(
            hashes[0],
            "f568726d7291983d6ba0e7fc5a00b242f0016ed38d0dd3930d86ced8963ba597"
        )
    }

    func testDigestRejectsEmptyPayload() {
        let empty = makePayload(cbor: Data())
        XCTAssertThrowsError(try SwapKitCardanoSigner.digest(payload: empty)) { err in
            guard case SwapKitCardanoSignerError.emptyPayload = err else {
                return XCTFail("expected .emptyPayload, got \(err)")
            }
        }
    }

    func testDigestRejectsMissingOuterArrayHeader() {
        // Strip the outer `84` byte — the walker must reject before hashing
        // a malformed envelope (otherwise we'd hash the wrong bytes and feed
        // a useless digest to MPC).
        var bad = Data(hexString: Self.unsignedCborHex)!
        bad.removeFirst()
        let payload = makePayload(cbor: bad)
        XCTAssertThrowsError(try SwapKitCardanoSigner.digest(payload: payload)) { err in
            guard case SwapKitCardanoSignerError.malformedEnvelope = err else {
                return XCTFail("expected .malformedEnvelope, got \(err)")
            }
        }
    }

    // MARK: - Signed-envelope assembly

    func testAssembleSignedTransactionProducesValidEnvelope() throws {
        // Dummy 32-byte vkey + 64-byte sig. We're not testing MPC here — just
        // verifying the CBOR splice keeps body / is_valid / aux_data
        // verbatim and replaces the empty witness_set with the correct
        // `{ 0: [[vkey, sig]] }` shape.
        let vkey = Data(repeating: 0, count: 32)
        let sig = Data(repeating: 0, count: 64)
        let unsigned = Data(hexString: Self.unsignedCborHex)!

        let signed = try SwapKitCardanoSigner.assembleSignedTransaction(
            unsignedCbor: unsigned,
            signature: sig,
            verificationKey: vkey
        )

        // Expected output, computed independently:
        //   array(4) header (84)
        //   + 131-byte body (verbatim)
        //   + witness: a1 00 81 82 + cbor_bytes(vkey, 34 bytes) + cbor_bytes(sig, 66 bytes)
        //   + is_valid (f5)
        //   + aux_data (f6)
        // = 1 + 131 + 104 + 1 + 1 = 238 bytes.
        XCTAssertEqual(signed.count, 238)
        XCTAssertEqual(signed[0], 0x84, "outer array(4) header preserved")

        // Body bytes preserved verbatim — drift here would invalidate the
        // signature even if the envelope re-encoded to the same hex string.
        let bodyRange = 1..<132
        let unsignedBody = unsigned[bodyRange]
        let signedBody = signed[bodyRange]
        XCTAssertEqual(Data(unsignedBody), Data(signedBody))

        // Witness immediately follows the body. Expected encoding:
        //   a1 00 81 82 5820 <32 vkey bytes> 5840 <64 sig bytes>
        let expectedWitnessHex =
            "a10081825820" +
            String(repeating: "00", count: 32) +
            "5840" +
            String(repeating: "00", count: 64)
        let witnessStart = 132
        let witnessEnd = witnessStart + 104
        XCTAssertEqual(
            Data(signed[witnessStart..<witnessEnd]).hexString,
            expectedWitnessHex,
            "witness_set must be `{ 0: [[vkey_32, sig_64]] }`"
        )

        // is_valid and aux_data tail bytes verbatim.
        XCTAssertEqual(signed[signed.count - 2], 0xF5)
        XCTAssertEqual(signed[signed.count - 1], 0xF6)
    }

    func testAssembleRejectsBadKeyLength() {
        let unsigned = Data(hexString: Self.unsignedCborHex)!
        XCTAssertThrowsError(try SwapKitCardanoSigner.assembleSignedTransaction(
            unsignedCbor: unsigned,
            signature: Data(repeating: 0, count: 64),
            verificationKey: Data(repeating: 0, count: 31)
        )) { err in
            guard case CardanoSignedTxBuilderError.invalidPublicKeyLength(let n) = err else {
                return XCTFail("expected .invalidPublicKeyLength, got \(err)")
            }
            XCTAssertEqual(n, 31)
        }
    }

    func testAssembleRejectsBadSignatureLength() {
        let unsigned = Data(hexString: Self.unsignedCborHex)!
        XCTAssertThrowsError(try SwapKitCardanoSigner.assembleSignedTransaction(
            unsignedCbor: unsigned,
            signature: Data(repeating: 0, count: 63),
            verificationKey: Data(repeating: 0, count: 32)
        )) { err in
            guard case CardanoSignedTxBuilderError.invalidSignatureLength(let n) = err else {
                return XCTFail("expected .invalidSignatureLength, got \(err)")
            }
            XCTAssertEqual(n, 63)
        }
    }

    // MARK: - Helpers

    private func makePayload(cbor: Data? = nil) -> SwapKitSwapPayload {
        let bytes = cbor ?? Data(hexString: Self.unsignedCborHex)!
        return SwapKitSwapPayload(
            fromCoin: makeAdaCoin(),
            toCoin: makeUsdcCoin(),
            fromAmount: BigInt(45_500_000),
            toAmountDecimal: 0,
            txType: "CARDANO_PREBUILT",
            txPayload: bytes,
            targetAddress: "addr1vy9sgnlkxkwg58axypgwllhgt522k045f0q7zst5faxqc2sgggj3a",
            inboundAddress: "addr1vy9sgnlkxkwg58axypgwllhgt522k045f0q7zst5faxqc2sgggj3a",
            memo: nil,
            subProvider: "NEAR",
            swapID: "test"
        )
    }

    private func makeAdaCoin() -> Coin {
        let meta = CoinMeta.make(chain: .cardano, ticker: "ADA", decimals: 6, isNativeToken: true)
        return Coin(
            asset: meta,
            address: "addr1v9yg8pmjamtkaenz602yfe8c0y25fe304qqwka67epx7vtszj8749",
            hexPublicKey: ""
        )
    }

    private func makeUsdcCoin() -> Coin {
        let meta = CoinMeta.make(chain: .ethereum, ticker: "USDC", decimals: 6, isNativeToken: false)
        return Coin(asset: meta, address: "0xtest", hexPublicKey: "")
    }
}
