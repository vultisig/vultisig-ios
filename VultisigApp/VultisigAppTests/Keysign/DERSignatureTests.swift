//
//  DERSignatureTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

/// Pins `encodeCanonicalDERSignature` against the non-canonical-DER broadcast
/// rejection this fix addresses: DKLS returns `r` as a fixed 32-byte scalar,
/// not a minimal-length big-endian value, so a leading `0x00` byte must be
/// stripped before encoding — otherwise the signature carries excess padding
/// a strict node's DER check rejects (BIP66 rule 3).
final class DERSignatureTests: XCTestCase {

    /// A single leading zero followed by a byte whose high bit is clear must
    /// be stripped entirely: it is not needed to keep the integer positive.
    func testStripsALeadingZeroByteWhenTheNextByteIsNotHigh() {
        var r = [UInt8](repeating: 0x11, count: 32)
        r[0] = 0x00
        r[1] = 0x01
        let s = [UInt8](repeating: 0x22, count: 32) // 0x22.. is far below the curve's half-order

        let der = encodeCanonicalDERSignature(r: r, s: s)
        let rEncoded = rIntegerBytes(from: der)

        XCTAssertEqual(rEncoded, Data(r.dropFirst()), "the redundant leading zero must not appear in the DER integer")
    }

    /// Two leading zero bytes followed by a high-bit byte must collapse to
    /// exactly one zero byte of padding, not two.
    func testCollapsesMultipleLeadingZerosToExactlyOneWhenTheNextByteIsHigh() {
        var r = [UInt8](repeating: 0x11, count: 32)
        r[0] = 0x00
        r[1] = 0x00
        r[2] = 0x80
        let s = [UInt8](repeating: 0x22, count: 32)

        let der = encodeCanonicalDERSignature(r: r, s: s)
        let rEncoded = rIntegerBytes(from: der)

        XCTAssertEqual(rEncoded, Data(r.dropFirst()), "exactly one 0x00 must remain ahead of the high-bit byte")
        XCTAssertEqual(rEncoded.first, 0x00)
    }

    /// A value with no leading zero byte and a high bit set still needs the
    /// sign-safety padding added, same as before this fix.
    func testStillPadsAHighBitLeadingByteWithNoExistingZero() {
        var r = [UInt8](repeating: 0x11, count: 32)
        r[0] = 0x80
        let s = [UInt8](repeating: 0x22, count: 32)

        let der = encodeCanonicalDERSignature(r: r, s: s)
        let rEncoded = rIntegerBytes(from: der)

        XCTAssertEqual(rEncoded, Data([0x00] + r), "a high-bit leading byte with no pre-existing zero still needs one added")
    }

    /// A value that is already minimal (no leading zero, no high bit) is
    /// untouched — this is the common case and must stay a no-op.
    func testLeavesAnAlreadyMinimalValueUnchanged() {
        var r = [UInt8](repeating: 0x11, count: 32)
        r[0] = 0x7f
        let s = [UInt8](repeating: 0x22, count: 32)

        let der = encodeCanonicalDERSignature(r: r, s: s)
        let rEncoded = rIntegerBytes(from: der)

        XCTAssertEqual(rEncoded, Data(r))
    }

    /// Extracts the bytes of the first (`r`) INTEGER from a DER
    /// `SEQUENCE { INTEGER, INTEGER }` produced by `encodeCanonicalDERSignature`.
    private func rIntegerBytes(from der: Data) -> Data {
        let bytes = [UInt8](der)
        precondition(bytes[0] == 0x30, "expected a DER SEQUENCE")
        precondition(bytes[2] == 0x02, "expected the first element to be an INTEGER")
        let rLen = Int(bytes[3])
        return Data(bytes[4..<(4 + rLen)])
    }
}
