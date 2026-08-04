//
//  TronPublicKeyFormatTests.swift
//  VultisigAppTests
//
//  A peer device joining a Tron keysign (e.g. Android initiating a
//  Freeze/Unfreeze) may send `KeysignPayload.coin.hexPublicKey` in the
//  standard compressed secp256k1 form rather than this app's
//  Tron-specific uncompressed one. `TronHelper.uncompressedPublicKey`
//  must accept both, or a validly cosigned transaction gets rejected
//  locally as "public key is invalid" even though the peer already
//  broadcast it successfully.
//

@testable import VultisigApp
import WalletCore
import XCTest

final class TronPublicKeyFormatTests: XCTestCase {

    private let compressedHex = "023e4b76861289ad4528b33c2fd21b3a5160cd37b3294234914e21efb6ed4a452b"

    private var expectedUncompressedData: Data {
        PublicKey(data: Data(hexString: compressedHex)!, type: .secp256k1)!.uncompressed.data
    }

    func testAcceptsCompressedPublicKey() throws {
        let result = try TronHelper.uncompressedPublicKey(fromHex: compressedHex)
        XCTAssertEqual(result.data, expectedUncompressedData)
    }

    func testAcceptsUncompressedPublicKey() throws {
        let extendedHex = expectedUncompressedData.hexString
        let result = try TronHelper.uncompressedPublicKey(fromHex: extendedHex)
        XCTAssertEqual(result.data, expectedUncompressedData)
    }

    func testRejectsNonHexString() {
        XCTAssertThrowsError(try TronHelper.uncompressedPublicKey(fromHex: "not-hex"))
    }

    func testRejectsValidHexThatIsNotAPublicKey() {
        XCTAssertThrowsError(try TronHelper.uncompressedPublicKey(fromHex: "deadbeef"))
    }
}
