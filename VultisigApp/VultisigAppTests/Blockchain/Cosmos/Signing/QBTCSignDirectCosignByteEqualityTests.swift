//
//  QBTCSignDirectCosignByteEqualityTests.swift
//  VultisigAppTests
//
//  CROSS-PLATFORM SIGNING GATE for the QBTC governance co-signing path.
//
//  When a Windows/SDK device initiates an arbitrary Cosmos message on QBTC
//  (e.g. a governance MsgVote) via the dApp `sign_and_broadcast` flow, it ships
//  the fully-formed `bodyBytes` + `authInfoBytes` + `chainId` + `accountNumber`
//  to every co-signer inside `KeysignPayload.signData.signDirect`. iOS must
//  reconstruct the EXACT same Cosmos `SignDoc`, hash it to the EXACT same
//  SHA-256, and assemble the EXACT same broadcast `TxRaw` — otherwise the
//  ML-DSA threshold signature is computed over a different pre-image and the
//  chain rejects it.
//
//  The expected byte vector (`QBTCCosignVector`) is DERIVED FROM THE
//  WINDOWS/SDK CONTRACT, not from iOS's own output, so this test actually pins
//  cross-platform agreement:
//
//    * MsgVote bytes   — `cosmjs-types` `MsgVote` (`/cosmos.gov.v1beta1.MsgVote`),
//      the exact encoder `messageRegistry.ts` wires into the QBTC dApp provider.
//    * Any / TxBody    — `encodeAnyMessage.ts` + `buildQBTCDirectPayload.ts`
//      (`protoString(1,typeUrl) ++ protoBytes(2,msg)`, then `protoBytes(1,any)`,
//      no memo for a vote).
//    * AuthInfo        — `buildQBTCDirectPayload.ts buildAuthInfo` with the
//      default fee (800 uqbtc, gas_limit 300000) and the ML-DSA pubkey Any.
//    * SignDoc / TxRaw — `buildQBTCSignedTxFromDirect.ts` + the SDK
//      `QBTCHelper.ts` (`packages/core/mpc/chains/cosmos/qbtc`).
//    * proto encoding  — `@vultisig/core-chain/.../protoEncoding.ts`, whose
//      proto3 default-elision (skip 0 varints / empty bytes / empty strings)
//      matches iOS's `appendProto*` helpers byte-for-byte.
//
//  If iOS's encoding ever drifts from that contract, these assertions fail —
//  which is the whole point of the gate.
//

@testable import VultisigApp
import CryptoKit
import VultisigCommonData
import XCTest

final class QBTCSignDirectCosignByteEqualityTests: XCTestCase {

    // MARK: - Helpers

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
            address: QBTCCosignVector.voter,
            hexPublicKey: QBTCCosignVector.mldsaPubKeyHex
        )
    }

    /// Builds a `KeysignPayload` carrying the Windows-supplied `signDirect`. The
    /// memo is intentionally empty (a Windows-initiated vote has no memo) — if
    /// iOS fell back to the memo path it would build a MsgSend SignDoc and the
    /// hash would not match. `chainSpecific` carries DELIBERATELY WRONG
    /// account/sequence/gas to prove the short-circuit ignores it: if iOS read
    /// these instead of the received signDirect bytes, the hash would differ.
    private static func makeSignDirectPayload(
        bodyBytesB64: String,
        authInfoBytesB64: String,
        accountNumber: String,
        memo: String = ""
    ) -> KeysignPayload {
        let signDirect = SignDirect(
            bodyBytes: bodyBytesB64,
            authInfoBytes: authInfoBytesB64,
            chainID: QBTCCosignVector.chainID,
            accountNumber: accountNumber
        )
        return KeysignPayload(
            coin: makeQBTCCoin(),
            toAddress: "",
            toAmount: 0,
            chainSpecific: .Cosmos(
                accountNumber: 999_999,
                sequence: 123_456,
                gas: 1,
                transactionType: 0,
                ibcDenomTrace: nil, gasLimit: nil
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
            signData: .signDirect(signDirect)
        )
    }

    // MARK: - GATE: SignDoc pre-image hash matches the Windows/SDK contract

    func testPreSignedImageHashMatchesWindowsVoteVector() throws {
        let payload = Self.makeSignDirectPayload(
            bodyBytesB64: QBTCCosignVector.bodyBytesB64,
            authInfoBytesB64: QBTCCosignVector.authInfoBytesB64,
            accountNumber: "100"
        )
        let hashes = try QBTCHelper.create().getPreSignedImageHash(keysignPayload: payload)
        XCTAssertEqual(hashes.count, 1)
        XCTAssertEqual(
            hashes[0],
            QBTCCosignVector.signDocSHA256Hex,
            "iOS SignDoc SHA-256 must equal the Windows/SDK-derived MsgVote vector"
        )
    }

    func testPreSignedImageHashIgnoresChainSpecificDrift() throws {
        // Same received signDirect, but a misleading memo + wrong chainSpecific.
        // The helper must use the round-tripped signDirect bytes, never local
        // chainSpecific or the memo.
        let payload = Self.makeSignDirectPayload(
            bodyBytesB64: QBTCCosignVector.bodyBytesB64,
            authInfoBytesB64: QBTCCosignVector.authInfoBytesB64,
            accountNumber: "100",
            memo: "QBTC_VOTE:NO:7"
        )
        let hashes = try QBTCHelper.create().getPreSignedImageHash(keysignPayload: payload)
        XCTAssertEqual(
            hashes[0],
            QBTCCosignVector.signDocSHA256Hex,
            "memo/chainSpecific must not affect the signDirect cosign hash"
        )
    }

    func testPreSignedImageHashOmitsAccountNumberFieldWhenZero() throws {
        // proto3 default-skip parity with cosmjs/core: accountNumber == 0 must
        // produce a SignDoc with field 4 omitted, not a zero varint.
        let payload = Self.makeSignDirectPayload(
            bodyBytesB64: QBTCCosignVector.bodyBytesB64,
            authInfoBytesB64: QBTCCosignVector.authInfoBytesB64,
            accountNumber: "0"
        )
        let hashes = try QBTCHelper.create().getPreSignedImageHash(keysignPayload: payload)
        XCTAssertEqual(
            hashes[0],
            QBTCCosignVector.signDocAccountZeroSHA256Hex,
            "accountNumber==0 must skip SignDoc field 4 (proto3 default), matching cosmjs"
        )
    }

    func testPreSignedImageHashAbstainSequenceZeroVector() throws {
        // Non-YES option + sequence 0 (SignerInfo.sequence field skipped).
        let payload = Self.makeSignDirectPayload(
            bodyBytesB64: QBTCCosignVector.abstainBodyBytesB64,
            authInfoBytesB64: QBTCCosignVector.abstainAuthInfoBytesB64,
            accountNumber: "5"
        )
        let hashes = try QBTCHelper.create().getPreSignedImageHash(keysignPayload: payload)
        XCTAssertEqual(hashes[0], QBTCCosignVector.abstainSignDocSHA256Hex)
    }

    // MARK: - GATE: final TxRaw / broadcast matches the Windows/SDK contract

    func testSignedTransactionTxRawMatchesWindowsVoteVector() throws {
        let payload = Self.makeSignDirectPayload(
            bodyBytesB64: QBTCCosignVector.bodyBytesB64,
            authInfoBytesB64: QBTCCosignVector.authInfoBytesB64,
            accountNumber: "100"
        )
        let signatures: [String: DilithiumKeysignResponse] = [
            QBTCCosignVector.signDocSHA256Hex: DilithiumKeysignResponse(
                msg: QBTCCosignVector.signDocSHA256Hex,
                signature: QBTCCosignVector.signatureHex
            )
        ]

        let result = try QBTCHelper.create().getSignedTransaction(
            keysignPayload: payload,
            signatures: signatures
        )

        // transactionHash = uppercased SHA-256 of TxRaw — must match the SDK.
        XCTAssertEqual(
            result.transactionHash,
            QBTCCosignVector.txRawSHA256HexUpper,
            "iOS TxRaw SHA-256 must equal the Windows/SDK-derived TxRaw hash"
        )

        // The broadcast JSON's tx_bytes must decode to a TxRaw that is:
        //   protoBytes(1,body) ++ protoBytes(2,authInfo) ++ protoBytes(3,sig)
        // assembled from the RECEIVED body/authInfo verbatim (no re-derivation).
        let txBytes = try Self.extractTxBytes(fromBroadcastJSON: result.rawTransaction)
        let body = try XCTUnwrap(Data(base64Encoded: QBTCCosignVector.bodyBytesB64))
        let authInfo = try XCTUnwrap(Data(base64Encoded: QBTCCosignVector.authInfoBytesB64))
        let signature = try XCTUnwrap(Data(hexString: QBTCCosignVector.signatureHex))
        var expectedTxRaw = Data()
        expectedTxRaw.appendProtoBytes(fieldNumber: 1, data: body)
        expectedTxRaw.appendProtoBytes(fieldNumber: 2, data: authInfo)
        expectedTxRaw.appendProtoBytes(fieldNumber: 3, data: signature)
        XCTAssertEqual(txBytes, expectedTxRaw, "TxRaw must reuse the received AuthInfo verbatim")

        // And that reconstructed TxRaw must hash to the pinned value.
        XCTAssertEqual(
            SHA256.hash(data: txBytes).map { String(format: "%02X", $0) }.joined(),
            QBTCCosignVector.txRawSHA256HexUpper
        )
    }

    func testSignedTransactionThrowsWhenSignatureMissing() {
        let payload = Self.makeSignDirectPayload(
            bodyBytesB64: QBTCCosignVector.bodyBytesB64,
            authInfoBytesB64: QBTCCosignVector.authInfoBytesB64,
            accountNumber: "100"
        )
        // Signature keyed by the wrong hash → must throw, never silently sign.
        let signatures: [String: DilithiumKeysignResponse] = [
            "00": DilithiumKeysignResponse(msg: "00", signature: QBTCCosignVector.signatureHex)
        ]
        XCTAssertThrowsError(
            try QBTCHelper.create().getSignedTransaction(keysignPayload: payload, signatures: signatures)
        )
    }

    // MARK: - Round-trip: signDirect survives the proto transport intact

    func testKeysignPayloadSignDirectRoundTripsThroughProto() throws {
        let original = Self.makeSignDirectPayload(
            bodyBytesB64: QBTCCosignVector.bodyBytesB64,
            authInfoBytesB64: QBTCCosignVector.authInfoBytesB64,
            accountNumber: "100"
        )

        // KeysignPayload -> VSKeysignPayload -> serialized proto -> back.
        let protoData = try original.mapToProtobuff().serializedData()
        let decodedProto = try VSKeysignPayload(serializedBytes: protoData)
        let restored = try KeysignPayload(proto: decodedProto)

        let signDirect = try XCTUnwrap(restored.signDirect)
        XCTAssertEqual(signDirect.bodyBytes, QBTCCosignVector.bodyBytesB64)
        XCTAssertEqual(signDirect.authInfoBytes, QBTCCosignVector.authInfoBytesB64)
        XCTAssertEqual(signDirect.chainID, QBTCCosignVector.chainID)
        XCTAssertEqual(signDirect.accountNumber, "100")

        // The signing pre-image must be identical on the peer that rebuilt the
        // payload from the wire — this is the cross-device guarantee.
        let originalHash = try QBTCHelper.create().getPreSignedImageHash(keysignPayload: original)
        let restoredHash = try QBTCHelper.create().getPreSignedImageHash(keysignPayload: restored)
        XCTAssertEqual(originalHash, restoredHash)
        XCTAssertEqual(restoredHash[0], QBTCCosignVector.signDocSHA256Hex)
    }

    func testSignDirectAccountNumberZeroRoundTripsThroughProto() throws {
        // Guards the proto3-default edge: accountNumber "0" must come back as
        // "0" (not dropped to empty) so the rebuilt SignDoc still omits field 4
        // and hashes identically.
        let original = Self.makeSignDirectPayload(
            bodyBytesB64: QBTCCosignVector.bodyBytesB64,
            authInfoBytesB64: QBTCCosignVector.authInfoBytesB64,
            accountNumber: "0"
        )
        let protoData = try original.mapToProtobuff().serializedData()
        let restored = try KeysignPayload(proto: VSKeysignPayload(serializedBytes: protoData))
        let signDirect = try XCTUnwrap(restored.signDirect)
        XCTAssertEqual(signDirect.accountNumber, "0")

        let hash = try QBTCHelper.create().getPreSignedImageHash(keysignPayload: restored)
        XCTAssertEqual(hash[0], QBTCCosignVector.signDocAccountZeroSHA256Hex)
    }

    // MARK: - Broadcast JSON parsing helper

    private static func extractTxBytes(fromBroadcastJSON json: String) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let dict = try XCTUnwrap(object as? [String: Any])
        XCTAssertEqual(dict["mode"] as? String, "BROADCAST_MODE_SYNC")
        let base64 = try XCTUnwrap(dict["tx_bytes"] as? String)
        return try XCTUnwrap(Data(base64Encoded: base64))
    }
}
