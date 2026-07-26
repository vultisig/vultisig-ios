//
//  CosmosCustomMessageTests.swift
//  VultisigApp
//

@testable import VultisigApp
import Foundation
import WalletCore
import XCTest

/// Cosmos-family dApp custom-message co-signing path. Cosmos SDK chains and
/// THORChain/Maya sign the sha256 of the message (Keplr ADR-36 signArbitrary
/// over the StdSignDoc bytes). keccak256 here — the EVM default in this code
/// path — diverges from the md5 message-ID the initiator derives, so
/// cross-platform co-signing 404s. Mirrors getCustomMessageHex.ts in
/// vultisig-windows and the fix in vultisig-android#5240.
final class CosmosCustomMessageTests: XCTestCase {

    private func makePayload(method: String, message: String, chain: String) -> CustomMessagePayload {
        CustomMessagePayload(
            method: method,
            message: message,
            vaultPublicKeyECDSA: "",
            vaultLocalPartyID: "",
            chain: chain
        )
    }

    func testThorChainHexMessageIsSha256Hashed() {
        let hexMessage = "0xabcdef0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d"
        let expected = Data(hex: hexMessage).sha256().hexString
        let payload = makePayload(method: "sign", message: hexMessage, chain: "THORChain")

        XCTAssertEqual(payload.keysignMessages, [expected])
    }

    func testNativeCosmosPlainTextMessageIsSha256Hashed() {
        let message = "Hello Vultisig"
        let expected = Data(message.utf8).sha256().hexString
        let payload = makePayload(method: "sign", message: message, chain: "Cosmos")

        XCTAssertEqual(payload.keysignMessages, [expected])
    }

    func testMayaChainMessageIsSha256Hashed() {
        let message = "Hello Maya"
        let expected = Data(message.utf8).sha256().hexString
        let payload = makePayload(method: "sign", message: message, chain: "MayaChain")

        XCTAssertEqual(payload.keysignMessages, [expected])
    }

    func testCosmosBranchAcceptsMixedCaseChainName() {
        let message = "case insensitive"
        let expected = Data(message.utf8).sha256().hexString
        for chain in ["thorchain", "THORChain", "THORCHAIN"] {
            let payload = makePayload(method: "sign", message: message, chain: chain)
            XCTAssertEqual(payload.keysignMessages, [expected], "Failed for chain: \(chain)")
        }
    }

    func testEvmMessageDoesNotTakeCosmosSha256Path() {
        // Guard against the Cosmos branch swallowing EVM custom messages: an
        // Ethereum personal_sign must NOT produce the sha256 digest.
        let message = "not a cosmos message"
        let sha256Digest = Data(message.utf8).sha256().hexString
        let payload = makePayload(method: "personal_sign", message: message, chain: "Ethereum")

        XCTAssertNotEqual(payload.keysignMessages, [sha256Digest])
    }
}
