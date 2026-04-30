//
//  QBTCClaimDispatchTests.swift
//  VultisigAppTests
//
//  Verifies QBTCHelper dispatches to the claim path when the
//  KeysignPayload carries a `qbtcClaimPayload`. The existing send
//  path is unchanged when the claim payload is nil.
//

import BigInt
@testable import VultisigApp
import VultisigCommonData
import XCTest

final class QBTCClaimDispatchTests: XCTestCase {
    /// Minimal MLDSA pubkey hex — content doesn't matter for byte parity, just
    /// a stable input. (Real pubkeys are ~1300 bytes for ML-DSA-44.)
    let mldsaPubKeyHex = String(repeating: "ab", count: 32)
    let qbtcAddress = "qbtc1abc"
    let accountNumber: UInt64 = 42
    let sequence: UInt64 = 3

    static let validClaim = QBTCClaimPayload(
        proofHex: String(repeating: "ff", count: 200),
        messageHashHex: String(repeating: "bb", count: 32),
        addressHashHex: String(repeating: "cc", count: 20),
        qbtcAddressHashHex: String(repeating: "dd", count: 32),
        pubKeyHashSha256Hex: String(repeating: "ee", count: 32),
        utxos: [ClaimableUtxo(txid: String(repeating: "aa", count: 32), vout: 0, amount: 100_000)]
    )

    // MARK: - QBTCClaimPayload.toClaimMessage

    func testToClaimMessageMapsAllFields() {
        let msg = Self.validClaim.toClaimMessage(claimer: qbtcAddress)
        XCTAssertEqual(msg.claimer, qbtcAddress)
        XCTAssertEqual(msg.utxos, Self.validClaim.utxos)
        XCTAssertEqual(msg.proofHex, Self.validClaim.proofHex)
        XCTAssertEqual(msg.messageHashHex, Self.validClaim.messageHashHex)
        XCTAssertEqual(msg.addressHashHex, Self.validClaim.addressHashHex)
        XCTAssertEqual(msg.qbtcAddressHashHex, Self.validClaim.qbtcAddressHashHex)
    }

    // MARK: - getPreSignedImageHash dispatches to the claim path

    func testGetPreSignedImageHashReturnsClaimSignDocHash() throws {
        let payload = makeClaimKeysignPayload()
        let helper = QBTCHelper.create()

        let hashes = try helper.getPreSignedImageHash(keysignPayload: payload)

        // Compute the expected hash directly via §3 + §7.
        let claimMessage = Self.validClaim.toClaimMessage(claimer: qbtcAddress)
        let bodyBytes = try QBTCHelper.buildClaimTxBody(claimMessage)
        let mldsaPubKey = Data(hexString: mldsaPubKeyHex)!
        let artifacts = QBTCHelper.buildClaimSignDoc(
            bodyBytes: bodyBytes,
            mldsaPublicKey: mldsaPubKey,
            accountNumber: accountNumber,
            sequence: sequence
        )

        XCTAssertEqual(hashes, [artifacts.signDocHashHex])
    }

    // MARK: - getSignedTransaction dispatches and looks up by hash

    func testGetSignedTransactionAssemblesClaimTxRaw() throws {
        let payload = makeClaimKeysignPayload()
        let helper = QBTCHelper.create()

        // Pre-compute the signDocHashHex the helper expects to find in the
        // signatures dict.
        let claimMessage = Self.validClaim.toClaimMessage(claimer: qbtcAddress)
        let bodyBytes = try QBTCHelper.buildClaimTxBody(claimMessage)
        let mldsaPubKey = Data(hexString: mldsaPubKeyHex)!
        let artifacts = QBTCHelper.buildClaimSignDoc(
            bodyBytes: bodyBytes,
            mldsaPublicKey: mldsaPubKey,
            accountNumber: accountNumber,
            sequence: sequence
        )

        let signatureHex = String(repeating: "ef", count: 96)
        let signatures: [String: DilithiumKeysignResponse] = [
            artifacts.signDocHashHex: DilithiumKeysignResponse(msg: artifacts.signDocHashHex, signature: signatureHex)
        ]

        let result = try helper.getSignedTransaction(keysignPayload: payload, signatures: signatures)

        // Expected TxRaw: same bodyBytes, same authInfoBytes, signature bytes.
        let signatureData = Data(hexString: signatureHex)!
        let expected = QBTCHelper.assembleClaimTxRaw(
            bodyBytes: bodyBytes,
            authInfoBytes: artifacts.authInfoBytes,
            mldsaSignature: signatureData
        )

        let expectedJSON = "{\"tx_bytes\":\"\(expected.txRawBytes.base64EncodedString())\",\"mode\":\"BROADCAST_MODE_SYNC\"}"
        XCTAssertEqual(result.rawTransaction, expectedJSON)
        XCTAssertEqual(result.transactionHash, expected.txHashHex)
    }

    func testGetSignedTransactionThrowsWhenSignatureMissing() throws {
        let payload = makeClaimKeysignPayload()
        let helper = QBTCHelper.create()

        // Signatures dict keyed by the wrong hash → should throw.
        let signatures: [String: DilithiumKeysignResponse] = [
            "wronghash": DilithiumKeysignResponse(msg: "wronghash", signature: String(repeating: "ef", count: 96))
        ]

        XCTAssertThrowsError(try helper.getSignedTransaction(keysignPayload: payload, signatures: signatures))
    }

    // MARK: - helpers

    private func makeClaimKeysignPayload() -> KeysignPayload {
        let asset = CoinMeta(
            chain: .qbtc,
            ticker: "QBTC",
            logo: "qbtc",
            decimals: 8,
            priceProviderId: "qbtc",
            contractAddress: "",
            isNativeToken: true
        )
        let coin = Coin(asset: asset, address: qbtcAddress, hexPublicKey: mldsaPubKeyHex)
        return KeysignPayload(
            coin: coin,
            toAddress: "",
            toAmount: BigInt(0),
            chainSpecific: .Cosmos(
                accountNumber: accountNumber,
                sequence: sequence,
                gas: 0,
                transactionType: VSTransactionType.qbtcClaimWithProof.rawValue,
                ibcDenomTrace: nil
            ),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: Self.validClaim,
            qbtcClaimContext: nil,
            skipBroadcast: false,
            signData: nil
        )
    }
}
