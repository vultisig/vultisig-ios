//
//  RippleCustomMessageTests.swift
//  VultisigApp
//

@testable import VultisigApp
import XCTest

/// XRPL (Ripple) off-chain message co-signing path. The browser extension
/// (vultisig-windows#4399) added GemWallet `signMessage()` over the shared MPC
/// custom-message keysign, and the initiator hashes the message with
/// SHA-512-half (the first 32 bytes of SHA-512). A Secure Vault iPhone acting
/// as co-signer must reproduce the identical digest, or the message-ID derived
/// from it diverges and the ceremony can never locate the setup message.
///
/// The expected digests below are computed OUTSIDE Swift (SHA-512 is
/// standardised, so `hashlib.sha512(bytes)[:32]` equals the extension's
/// `sha512(bytes).slice(0, 32)`), so these tests pin cross-platform byte
/// identity rather than merely re-deriving iOS's own output.
final class RippleCustomMessageTests: XCTestCase {

    private func makePayload(method: String, message: String, chain: String = "Ripple") -> CustomMessagePayload {
        CustomMessagePayload(
            method: method,
            message: message,
            vaultPublicKeyECDSA: "",
            vaultLocalPartyID: "",
            chain: chain
        )
    }

    func testUtf8MessageHashesToSha512Half() {
        // "Hello, XRPL!" → hashlib.sha512(bytes)[:32].hex()
        let payload = makePayload(method: "sign_message", message: "Hello, XRPL!")
        XCTAssertEqual(
            payload.keysignMessages,
            ["f6805caef386076db074419d22a349341b0fa09c17838a2bdee43b2dc73cb988"]
        )
    }

    func testHexMessageIsDecodedBeforeHashing() {
        // 0xdeadbeef → sha512(<deadbeef bytes>)[:32], NOT sha512("0xdeadbeef" utf8).
        // The shared 0x-decode must run before the digest, matching the
        // extension's `Buffer.from(stripHexPrefix(message), 'hex')`.
        let payload = makePayload(method: "sign_message", message: "0xdeadbeef")
        XCTAssertEqual(
            payload.keysignMessages,
            ["1284b2d521535196f22175d5f558104220a6ad7680e78b49fa6f20e57ea7b185"]
        )
    }

    func testDigestIsLowercaseSha512HalfShape() {
        // 32 bytes = 64 lowercase hex chars, no 0x prefix — the extension emits
        // Buffer.toString('hex') (lowercase). The TXN\0 prefix + uppercasing in
        // Ripple.swift's transaction-ID path must NOT leak in here.
        let digest = makePayload(method: "sign_message", message: "abc").keysignMessages[0]
        XCTAssertEqual(digest.count, 64)
        XCTAssertFalse(digest.hasPrefix("0x"))
        XCTAssertEqual(digest, digest.lowercased())
    }

    func testRippleCaseAcceptsLowercaseAndMixedCase() {
        for chain in ["ripple", "Ripple", "RIPPLE"] {
            let payload = makePayload(method: "sign_message", message: "Hello, XRPL!", chain: chain)
            XCTAssertEqual(
                payload.keysignMessages,
                ["f6805caef386076db074419d22a349341b0fa09c17838a2bdee43b2dc73cb988"],
                "chain string \"\(chain)\" should match the Ripple branch"
            )
        }
    }

    func testRippleBranchTakesPrecedenceOverSolanaRawFallthrough() {
        // Without the Ripple branch, method "sign_message" + chain "ripple"
        // would miss every method branch and fall through to the raw-bytes
        // path (return [data.hexString]) — the extension'd sign the plaintext,
        // not its digest. Assert we hash instead of passing through.
        let payload = makePayload(method: "sign_message", message: "Hello, XRPL!")
        XCTAssertNotEqual(
            payload.keysignMessages,
            [Data("Hello, XRPL!".utf8).hexString],
            "raw message bytes slipped through — the Ripple digest branch didn't run"
        )
    }

    func testRippleBranchTakesPrecedenceOverEthSignTypedDataV4() {
        // The branch must run independent of `method`, like Cardano. A misrouted
        // eth_signTypedData_v4 on a Ripple payload must not hit the EIP-712 path.
        let payload = makePayload(method: "eth_signTypedData_v4", message: "Hello, XRPL!")
        XCTAssertEqual(
            payload.keysignMessages,
            ["f6805caef386076db074419d22a349341b0fa09c17838a2bdee43b2dc73cb988"]
        )
    }
}
