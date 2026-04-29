//
//  QBTCClaimSignDocTests.swift
//  VultisigAppTests
//
//  Wire-format byte-parity tests for the claim AuthInfo, SignDoc, and
//  TxRaw assembly. Mirrors vultisig-windows/.../buildClaimSignDoc.ts.
//

@testable import VultisigApp
import WalletCore
import XCTest

final class QBTCClaimSignDocTests: XCTestCase {
    // Realistic fixture sizes: MLDSA-44 pubkey is ~1300 bytes; we use a
    // small placeholder here since the test only checks structure, not key validity.
    let mldsaPubKey = Data(repeating: 0xab, count: 32)
    let bodyBytes = Data(repeating: 0xcd, count: 64)
    let signature = Data(repeating: 0xef, count: 96)

    // MARK: - buildClaimAuthInfo

    func testAuthInfoUsesMldsaPubKeyTypeURL() {
        let authInfo = QBTCHelper.buildClaimAuthInfo(mldsaPublicKey: mldsaPubKey, sequence: 0)

        let typeURLBytes = QBTCClaimConfig.mldsaPubKeyTypeURL.data(using: .utf8)!
        XCTAssertTrue(authInfo.contains(subData: typeURLBytes),
                      "AuthInfo must embed /cosmos.crypto.mldsa.PubKey")
    }

    /// AuthInfo MUST be byte-equal to a manual reconstruction:
    /// signer_infos[0] (pubkey + ModeInfo.Single direct + sequence) +
    /// fee (gas_limit only — NO fee coins).
    func testAuthInfoMatchesManualReconstruction() {
        let sequence: UInt64 = 5
        let authInfo = QBTCHelper.buildClaimAuthInfo(mldsaPublicKey: mldsaPubKey, sequence: sequence)

        // Reconstruct by hand using the same primitives.
        var pubKeyMsg = Data()
        pubKeyMsg.appendProtoBytes(fieldNumber: 1, data: mldsaPubKey)

        var pubKeyAny = Data()
        pubKeyAny.appendProtoString(fieldNumber: 1, value: "/cosmos.crypto.mldsa.PubKey")
        pubKeyAny.appendProtoBytes(fieldNumber: 2, data: pubKeyMsg)

        var singleMode = Data()
        singleMode.appendProtoVarint(fieldNumber: 1, value: 1) // SIGN_MODE_DIRECT

        var modeInfo = Data()
        modeInfo.appendProtoBytes(fieldNumber: 1, data: singleMode)

        var signerInfo = Data()
        signerInfo.appendProtoBytes(fieldNumber: 1, data: pubKeyAny)
        signerInfo.appendProtoBytes(fieldNumber: 2, data: modeInfo)
        signerInfo.appendProtoVarint(fieldNumber: 3, value: sequence)

        var fee = Data()
        fee.appendProtoVarint(fieldNumber: 2, value: 300_000) // gas_limit only

        var expected = Data()
        expected.appendProtoBytes(fieldNumber: 1, data: signerInfo)
        expected.appendProtoBytes(fieldNumber: 2, data: fee)

        XCTAssertEqual(authInfo, expected)
    }

    /// `sequence = 0` is the legitimate fresh-account state. Proto3
    /// default-skip means the sequence varint is OMITTED in that case
    /// — verify the encoder does that and the chain accepts it.
    func testAuthInfoSkipsZeroSequence() {
        let authInfoZero = QBTCHelper.buildClaimAuthInfo(mldsaPublicKey: mldsaPubKey, sequence: 0)
        let authInfoOne = QBTCHelper.buildClaimAuthInfo(mldsaPublicKey: mldsaPubKey, sequence: 1)

        // The sequence=1 encoding adds the field 3 tag + value (2 bytes),
        // so it MUST be 2 bytes longer than the sequence=0 one.
        XCTAssertEqual(authInfoOne.count, authInfoZero.count + 2)
    }

    /// AuthInfo MUST NOT contain a fee coin denom string. Search for
    /// "qbtc" UTF-8 bytes — the claim is gas-free.
    func testAuthInfoOmitsFeeCoins() {
        let authInfo = QBTCHelper.buildClaimAuthInfo(mldsaPublicKey: mldsaPubKey, sequence: 1)

        let qbtcBytes = "qbtc".data(using: .utf8)!
        XCTAssertFalse(authInfo.contains(subData: qbtcBytes),
                       "Claim AuthInfo must NOT include a fee coin denom (gas-free)")
    }

    // MARK: - buildClaimSignDoc

    func testSignDocMatchesManualReconstructionAndHashesCorrectly() {
        let accountNumber: UInt64 = 42
        let sequence: UInt64 = 3

        let result = QBTCHelper.buildClaimSignDoc(
            bodyBytes: bodyBytes,
            mldsaPublicKey: mldsaPubKey,
            accountNumber: accountNumber,
            sequence: sequence
        )

        // Reconstruct the SignDoc by hand.
        let expectedAuthInfo = QBTCHelper.buildClaimAuthInfo(
            mldsaPublicKey: mldsaPubKey, sequence: sequence
        )
        var expectedSignDoc = Data()
        expectedSignDoc.appendProtoBytes(fieldNumber: 1, data: bodyBytes)
        expectedSignDoc.appendProtoBytes(fieldNumber: 2, data: expectedAuthInfo)
        expectedSignDoc.appendProtoString(fieldNumber: 3, value: QBTCClaimConfig.chainId)
        expectedSignDoc.appendProtoVarint(fieldNumber: 4, value: accountNumber)

        XCTAssertEqual(result.authInfoBytes, expectedAuthInfo)
        XCTAssertEqual(result.signDocBytes, expectedSignDoc)
        XCTAssertEqual(result.signDocHashHex, Self.hex(Hash.sha256(data: expectedSignDoc)))
        XCTAssertEqual(result.signDocHashHex.count, 64)
    }

    func testSignDocSkipsZeroAccountNumber() {
        let zero = QBTCHelper.buildClaimSignDoc(
            bodyBytes: bodyBytes,
            mldsaPublicKey: mldsaPubKey,
            accountNumber: 0,
            sequence: 0
        )
        let one = QBTCHelper.buildClaimSignDoc(
            bodyBytes: bodyBytes,
            mldsaPublicKey: mldsaPubKey,
            accountNumber: 1,
            sequence: 0
        )
        // Field 4 with value 1 adds 2 bytes (tag + varint(1)); value 0 is omitted.
        XCTAssertEqual(one.signDocBytes.count, zero.signDocBytes.count + 2)
    }

    func testSignDocUsesConfigChainIdByDefault() {
        let result = QBTCHelper.buildClaimSignDoc(
            bodyBytes: bodyBytes,
            mldsaPublicKey: mldsaPubKey,
            accountNumber: 1,
            sequence: 0
        )
        let chainIdBytes = QBTCClaimConfig.chainId.data(using: .utf8)!
        XCTAssertTrue(result.signDocBytes.contains(subData: chainIdBytes))
    }

    // MARK: - assembleClaimTxRaw

    func testTxRawMatchesManualReconstruction() {
        let authInfoBytes = QBTCHelper.buildClaimAuthInfo(mldsaPublicKey: mldsaPubKey, sequence: 1)
        let result = QBTCHelper.assembleClaimTxRaw(
            bodyBytes: bodyBytes,
            authInfoBytes: authInfoBytes,
            mldsaSignature: signature
        )

        var expected = Data()
        expected.appendProtoBytes(fieldNumber: 1, data: bodyBytes)
        expected.appendProtoBytes(fieldNumber: 2, data: authInfoBytes)
        expected.appendProtoBytes(fieldNumber: 3, data: signature)

        XCTAssertEqual(result.txRawBytes, expected)
    }

    // MARK: - private helpers

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    func testTxRawHashIsUppercaseHexOfSha256() {
        let authInfoBytes = QBTCHelper.buildClaimAuthInfo(mldsaPublicKey: mldsaPubKey, sequence: 1)
        let result = QBTCHelper.assembleClaimTxRaw(
            bodyBytes: bodyBytes,
            authInfoBytes: authInfoBytes,
            mldsaSignature: signature
        )

        let expectedHash = Self.hex(Hash.sha256(data: result.txRawBytes)).uppercased()
        XCTAssertEqual(result.txHashHex, expectedHash)
        XCTAssertEqual(result.txHashHex.count, 64)
        XCTAssertEqual(result.txHashHex, result.txHashHex.uppercased(),
                       "tx hash hex MUST be uppercased to match SDK + windows behaviour")
    }
}

// MARK: - test helper

private extension Data {
    /// Naive substring check on raw bytes — fine for small fixtures.
    func contains(subData: Data) -> Bool {
        guard !subData.isEmpty, subData.count <= self.count else { return false }
        for offset in 0...(self.count - subData.count) {
            if self.subdata(in: offset..<(offset + subData.count)) == subData {
                return true
            }
        }
        return false
    }
}
