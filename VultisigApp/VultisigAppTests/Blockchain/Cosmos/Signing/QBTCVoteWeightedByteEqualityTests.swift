//
//  QBTCVoteWeightedByteEqualityTests.swift
//  VultisigAppTests
//
//  CROSS-PLATFORM SIGNING GATE for the QBTC governance MsgVoteWeighted path,
//  the weighted-vote analogue of `QBTCSignDirectCosignByteEqualityTests`.
//
//  Unlike the single-vote cosign gate (which feeds Windows-supplied
//  signDirect bytes), this exercises the INITIATOR memo path: iOS builds the
//  weighted vote itself from the `QBTC_VOTEW:<id>:OPT=W,...` memo via
//  `QBTCHelper.buildMsgVoteWeighted`. The expected SignDoc hash + TxRaw hash
//  are derived from the proto / cosmjs contract (see
//  `QBTCVoteWeightedVector`), so if iOS's hand-rolled MsgVoteWeighted
//  encoding ever drifts from what a cosmjs peer signs, these assertions fail.
//

@testable import VultisigApp
import CryptoKit
import VultisigCommonData
import XCTest

final class QBTCVoteWeightedByteEqualityTests: XCTestCase {

    private static func makeQBTCCoin() -> Coin {
        let meta = CoinMeta(
            chain: .qbtc,
            ticker: "QBTC",
            logo: "qbtc",
            decimals: 8,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(
            asset: meta,
            address: QBTCVoteWeightedVector.voter,
            hexPublicKey: QBTCVoteWeightedVector.mldsaPubKeyHex
        )
    }

    /// Builds the `.vote` KeysignPayload exactly as the weighted-vote tab
    /// resolves to: the `QBTC_VOTEW:` memo via the non-signDirect path, with
    /// account 100 / sequence 7 / the default fee — matching the vector.
    private static func makeWeightedVotePayload(memo: String = QBTCVoteWeightedVector.memo) -> KeysignPayload {
        KeysignPayload(
            coin: makeQBTCCoin(),
            toAddress: "",
            toAmount: 0,
            chainSpecific: .Cosmos(
                accountNumber: 100,
                sequence: 7,
                gas: 800,
                transactionType: VSTransactionType.vote.rawValue,
                ibcDenomTrace: nil
            ),
            utxos: [],
            memo: memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "iPhone-test",
            libType: LibType.GG20.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }

    // MARK: - GATE: SignDoc pre-image hash matches the proto/cosmjs contract

    func testWeightedVotePreSignedImageHashMatchesVector() throws {
        let payload = Self.makeWeightedVotePayload()
        let hashes = try QBTCHelper.create().getPreSignedImageHash(keysignPayload: payload)
        XCTAssertEqual(hashes.count, 1)
        XCTAssertEqual(
            hashes[0],
            QBTCVoteWeightedVector.signDocSHA256Hex,
            "iOS MsgVoteWeighted SignDoc SHA-256 must equal the proto/cosmjs-derived vector"
        )
    }

    // MARK: - GATE: final TxRaw / broadcast matches the contract

    func testWeightedVoteSignedTransactionTxRawMatchesVector() throws {
        let payload = Self.makeWeightedVotePayload()
        let signatures: [String: DilithiumKeysignResponse] = [
            QBTCVoteWeightedVector.signDocSHA256Hex: DilithiumKeysignResponse(
                msg: QBTCVoteWeightedVector.signDocSHA256Hex,
                signature: QBTCVoteWeightedVector.signatureHex
            )
        ]

        let result = try QBTCHelper.create().getSignedTransaction(
            keysignPayload: payload,
            signatures: signatures
        )

        XCTAssertEqual(
            result.transactionHash,
            QBTCVoteWeightedVector.txRawSHA256HexUpper,
            "iOS weighted-vote TxRaw SHA-256 must equal the proto/cosmjs-derived TxRaw hash"
        )

        // The body inside the broadcast must equal the contract bodyBytes verbatim.
        let txBytes = try Self.extractTxBytes(fromBroadcastJSON: result.rawTransaction)
        let body = try XCTUnwrap(Data(base64Encoded: QBTCVoteWeightedVector.bodyBytesB64))
        let authInfo = try XCTUnwrap(Data(base64Encoded: QBTCVoteWeightedVector.authInfoBytesB64))
        let signature = try XCTUnwrap(Data(hexString: QBTCVoteWeightedVector.signatureHex))
        var expectedTxRaw = Data()
        expectedTxRaw.appendProtoBytes(fieldNumber: 1, data: body)
        expectedTxRaw.appendProtoBytes(fieldNumber: 2, data: authInfo)
        expectedTxRaw.appendProtoBytes(fieldNumber: 3, data: signature)
        XCTAssertEqual(txBytes, expectedTxRaw, "weighted-vote TxRaw must match the contract body/authInfo")
    }

    // MARK: - Weight formatting (canonical cosmos.Dec)

    func testLegacyDecStringCanonicalizesWeights() {
        XCTAssertEqual(QBTCHelper.legacyDecString(from: "0.7"), "0.700000000000000000")
        XCTAssertEqual(QBTCHelper.legacyDecString(from: ".3"), "0.300000000000000000")
        XCTAssertEqual(QBTCHelper.legacyDecString(from: "1"), "1.000000000000000000")
        XCTAssertEqual(QBTCHelper.legacyDecString(from: "0.333333333333333333"), "0.333333333333333333")
        // Truncates beyond 18 fractional digits.
        XCTAssertEqual(QBTCHelper.legacyDecString(from: "0.1234567890123456789"), "0.123456789012345678")
    }

    func testLegacyDecStringRejectsJunk() {
        XCTAssertNil(QBTCHelper.legacyDecString(from: ""))
        XCTAssertNil(QBTCHelper.legacyDecString(from: "abc"))
        XCTAssertNil(QBTCHelper.legacyDecString(from: "-0.5"))
        XCTAssertNil(QBTCHelper.legacyDecString(from: "0.5x"))
    }

    func testParseWeightedOptionsMapsTokensToProtoInts() throws {
        let options = try QBTCHelper.parseWeightedOptions("YES=0.7,ABSTAIN=0.3")
        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(options[0].option, 1)
        XCTAssertEqual(options[0].weight, "0.700000000000000000")
        XCTAssertEqual(options[1].option, 2)
        XCTAssertEqual(options[1].weight, "0.300000000000000000")
    }

    func testParseWeightedOptionsThrowsOnMalformed() {
        XCTAssertThrowsError(try QBTCHelper.parseWeightedOptions("YES"))
        XCTAssertThrowsError(try QBTCHelper.parseWeightedOptions("YES=abc"))
    }

    // MARK: - Helper

    private static func extractTxBytes(fromBroadcastJSON json: String) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let dict = try XCTUnwrap(object as? [String: Any])
        XCTAssertEqual(dict["mode"] as? String, "BROADCAST_MODE_SYNC")
        let base64 = try XCTUnwrap(dict["tx_bytes"] as? String)
        return try XCTUnwrap(Data(base64Encoded: base64))
    }
}
