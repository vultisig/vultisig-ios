//
//  CardanoCustomMessageTests.swift
//  VultisigApp
//

@testable import VultisigApp
import XCTest

/// Cardano CIP-30 dApp co-signing path. The Windows extension
/// (vultisig-windows#3766) pre-computes the bytes that need signing — Blake2b-
/// 256 of the tx body for `signTx`, or the COSE_Sign1 Sig_structure for
/// `signData` — and ships them through the keysign protocol as the
/// CustomMessagePayload message. iOS must sign those bytes verbatim, NOT
/// re-hash with keccak256 (which is the Ethereum/EVM default in this code path).
final class CardanoCustomMessageTests: XCTestCase {

    private func makePayload(method: String, message: String) -> CustomMessagePayload {
        CustomMessagePayload(
            method: method,
            message: message,
            vaultPublicKeyECDSA: "",
            vaultLocalPartyID: "",
            chain: "Cardano"
        )
    }

    func testSignTxBytesArePassedThroughVerbatim() {
        // Realistic 32-byte Blake2b digest as hex (what the extension would ship for signTx).
        let blake2bHex = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"
        let payload = makePayload(method: "signTx", message: "0x\(blake2bHex)")
        XCTAssertEqual(payload.keysignMessages, [blake2bHex])
    }

    func testSignDataBytesArePassedThroughVerbatim() {
        // COSE Sig_structure bytes — opaque; iOS must not re-hash.
        let coseHex = "8443a10127a058246b736b6e07"
        let payload = makePayload(method: "signData", message: "0x\(coseHex)")
        XCTAssertEqual(payload.keysignMessages, [coseHex])
    }

    func testCardanoCaseAcceptsLowercaseAndMixedCase() {
        let blake2bHex = "deadbeef" + String(repeating: "00", count: 28)
        let messages = [
            CustomMessagePayload(method: "signTx", message: "0x\(blake2bHex)", vaultPublicKeyECDSA: "", vaultLocalPartyID: "", chain: "cardano"),
            CustomMessagePayload(method: "signTx", message: "0x\(blake2bHex)", vaultPublicKeyECDSA: "", vaultLocalPartyID: "", chain: "Cardano"),
            CustomMessagePayload(method: "signTx", message: "0x\(blake2bHex)", vaultPublicKeyECDSA: "", vaultLocalPartyID: "", chain: "CARDANO")
        ]
        for payload in messages {
            XCTAssertEqual(payload.keysignMessages, [blake2bHex])
        }
    }

    func testCardanoBranchTakesPrecedenceOverKeccakFallthrough() {
        // Without the Cardano branch, method "signTx" + chain "cardano" would
        // fall into the (method != "sign_message" && chain != "solana") path
        // and produce a keccak256 digest. Assert we DON'T do that.
        let payload = makePayload(method: "signTx", message: "0xdeadbeef")
        let result = payload.keysignMessages
        XCTAssertEqual(result, ["deadbeef"])
        XCTAssertNotEqual(result.first?.count, 64,
                          "Got 64-char hex — looks like a keccak256 hash slipped through")
    }

    func testCardanoBranchTakesPrecedenceOverEthSignTypedDataV4() {
        // The Cardano branch must run independent of `method`. A payload with
        // `method == eth_signTypedData_v4` and `chain == cardano` must NOT be
        // misrouted into the EIP-712 path; it stays on the verbatim path.
        let blake2bHex = "deadbeef" + String(repeating: "00", count: 28)
        let payload = makePayload(method: "eth_signTypedData_v4", message: "0x\(blake2bHex)")
        XCTAssertEqual(payload.keysignMessages, [blake2bHex])
    }
}
