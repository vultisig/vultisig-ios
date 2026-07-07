//
//  TssSignatureTests.swift
//  VultisigApp
//
//  Pins `TssKeysignResponse.getSignature()` for the EdDSA path: `r`/`s` arrive
//  as big-endian scalar hex from tss-lib (`hex.EncodeToString(bigInt.Bytes())`),
//  which strips leading zero bytes. Each half must be left-padded to 32 bytes
//  *before* being reversed into the little-endian R || S Ed25519 wants —
//  otherwise a scalar with a high-order zero byte produces a truncated half and
//  a sub-64-byte signature that fails verification (an intermittent, vault- and
//  value-dependent "signature verification failed").
//

@testable import VultisigApp
import Tss
import WalletCore
import XCTest

final class TssSignatureTests: XCTestCase {

    private func response(r: String, s: String) -> TssKeysignResponse {
        let resp = TssKeysignResponse()
        resp.r = r
        resp.s = s
        return resp
    }

    // MARK: - Byte-level padding

    /// A full-width (64-char) `r` and a short (62-char) `s` — `s`'s leading zero
    /// byte was stripped by `big.Int.Bytes()`. The result is exactly 64 bytes,
    /// each half reversed, with the missing high byte restored as the last byte
    /// of the reversed `s`.
    func testShortComponentIsLeftPaddedBeforeReversal() throws {
        let r = String(repeating: "11", count: 32) // 32 bytes
        let s = String(repeating: "22", count: 31) // 31 bytes — high zero byte stripped

        let signature = try response(r: r, s: s).getSignature().get()

        XCTAssertEqual(signature.count, 64)
        XCTAssertEqual(signature.prefix(32), Data(repeating: 0x11, count: 32))
        // Reversed padded s = [0x22 × 31, 0x00].
        XCTAssertEqual(signature.suffix(32), Data(repeating: 0x22, count: 31) + Data([0x00]))
    }

    /// Both halves already full width (the common case) are unchanged apart from
    /// the byte-order reversal — the fix is a no-op for well-formed signatures.
    func testFullWidthComponentsOnlyReversed() throws {
        let r = "0102" + String(repeating: "00", count: 30) // 32 bytes, big-endian
        let s = "0304" + String(repeating: "00", count: 30)

        let signature = try response(r: r, s: s).getSignature().get()

        XCTAssertEqual(signature.count, 64)
        // Reverse of [0x01,0x02,0x00×30] = [0x00×30,0x02,0x01].
        XCTAssertEqual(signature.prefix(32), Data(repeating: 0x00, count: 30) + Data([0x02, 0x01]))
        XCTAssertEqual(signature.suffix(32), Data(repeating: 0x00, count: 30) + Data([0x04, 0x03]))
    }

    /// An odd-length hex string (a stripped leading nibble) is left-padded a
    /// nibble and parsed, rather than being rejected outright as before.
    func testOddLengthHexIsParsedNotRejected() throws {
        let r = "abc" // -> 0x0abc, big-endian 2 bytes
        let s = String(repeating: "33", count: 32)

        let signature = try response(r: r, s: s).getSignature().get()

        XCTAssertEqual(signature.count, 64)
        // Reverse of [0x0a,0xbc] padded to 32 = [0xbc,0x0a,0x00×30].
        XCTAssertEqual(signature.prefix(32), Data([0xbc, 0x0a]) + Data(repeating: 0x00, count: 30))
    }

    /// An over-long (> 32-byte) component is genuine corruption and is rejected,
    /// preserving the fail-closed behaviour for malformed input.
    func testOverLongComponentIsRejected() {
        let r = String(repeating: "aa", count: 33) // 33 bytes
        let s = String(repeating: "22", count: 32)

        switch response(r: r, s: s).getSignature() {
        case .success:
            XCTFail("expected an over-long r component to be rejected")
        case .failure:
            break
        }
    }

    // MARK: - Real-signature round-trip

    /// For a batch of real Ed25519 signatures, reformatting each into the TSS
    /// wire form (big-endian halves with leading zeros stripped, exactly as
    /// tss-lib does) and back through `getSignature()` reproduces the original
    /// 64-byte signature and verifies against the key. The batch guarantees at
    /// least some signatures have a high-order zero byte, exercising the padding
    /// path end-to-end.
    func testRoundTripRebuildsAndVerifiesRealSignatures() throws {
        let privateKey = try XCTUnwrap(PrivateKey(data: Data(repeating: 0x2A, count: 32)))
        let publicKey = privateKey.getPublicKeyEd25519()

        for i in 0..<40 {
            let message = Data((String(repeating: "m", count: i) + "vultisig").utf8).sha256()
            let realSig = try XCTUnwrap(privateKey.sign(digest: message, curve: .ed25519))
            XCTAssertEqual(realSig.count, 64)

            let resp = response(
                r: tssHex(fromLittleEndianHalf: realSig.prefix(32)),
                s: tssHex(fromLittleEndianHalf: realSig.suffix(32))
            )
            let rebuilt = try resp.getSignature().get()

            XCTAssertEqual(rebuilt, realSig, "round-trip mismatch for message \(i)")
            XCTAssertTrue(publicKey.verify(signature: rebuilt, message: message), "verify failed for message \(i)")
        }
    }

    /// Mimics tss-lib's `hex.EncodeToString(bigInt.Bytes())`: reverse a
    /// little-endian half to big-endian, then drop leading zero bytes.
    private func tssHex(fromLittleEndianHalf half: Data) -> String {
        var bigEndian = Array(half.reversed())
        while bigEndian.first == 0 { bigEndian.removeFirst() }
        return Data(bigEndian).hexString
    }
}
