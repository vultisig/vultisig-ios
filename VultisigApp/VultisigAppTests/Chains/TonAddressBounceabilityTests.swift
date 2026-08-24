//
//  TonAddressBounceabilityTests.swift
//  VultisigApp
//

@testable import VultisigApp
import XCTest

final class TonAddressBounceabilityTests: XCTestCase {
    // Same underlying account (workchain 0, hash from a real mainnet address
    // used elsewhere in the test suite), re-encoded with each bounce/network
    // flag combination so the four cases are directly comparable.
    private let bounceableMainnet = "EQCIcjES4cQET0z6nRixZ0MdvTB4u3_8triztLSrIIrDkpgJ"
    private let nonBounceableMainnet = "UQCIcjES4cQET0z6nRixZ0MdvTB4u3_8triztLSrIIrDksXM"
    private let bounceableTestnet = "kQCIcjES4cQET0z6nRixZ0MdvTB4u3_8triztLSrIIrDkiOD"
    private let nonBounceableTestnet = "0QCIcjES4cQET0z6nRixZ0MdvTB4u3_8triztLSrIIrDkn5G"
    private let rawAddress = "0:88723112e1c4044f4cfa9d18b167431dbd3078bb7ffcb6b8b3b4b4ab208ac392"

    func testBounceableMainnetAddressReturnsTrue() {
        XCTAssertEqual(TonAddressBounceability.isBounceable(bounceableMainnet), true)
    }

    func testNonBounceableMainnetAddressReturnsFalse() {
        XCTAssertEqual(TonAddressBounceability.isBounceable(nonBounceableMainnet), false)
    }

    func testBounceableTestnetAddressReturnsTrue() {
        XCTAssertEqual(TonAddressBounceability.isBounceable(bounceableTestnet), true)
    }

    func testNonBounceableTestnetAddressReturnsFalse() {
        XCTAssertEqual(TonAddressBounceability.isBounceable(nonBounceableTestnet), false)
    }

    func testRawAddressReturnsNil() {
        XCTAssertNil(TonAddressBounceability.isBounceable(rawAddress))
    }

    func testGarbageAddressReturnsNil() {
        XCTAssertNil(TonAddressBounceability.isBounceable("garbage"))
    }

    func testEmptyAddressReturnsNil() {
        XCTAssertNil(TonAddressBounceability.isBounceable(""))
    }

    func testValidLengthButIllegalTagReturnsNil() {
        // Right length, but a tag byte outside the four legal TON tags: intent
        // is unknown, not non-bounceable.
        let bytes = Data([UInt8](repeating: 0x00, count: 36))
        XCTAssertNil(TonAddressBounceability.isBounceable(bytes.base64EncodedString()))
    }

    func testMutatedChecksumReturnsNil() {
        // A valid address with its final checksum byte flipped must not be trusted.
        let mutated = String(bounceableMainnet.dropLast()) + "K"
        XCTAssertNil(TonAddressBounceability.isBounceable(mutated))
    }

    func testNonCanonicalBase64ReturnsNil() {
        // The same bytes in standard (non-URL-safe) Base64 is not a canonical
        // TON friendly address.
        let standard = bounceableMainnet.replacingOccurrences(of: "_", with: "/")
        XCTAssertNil(TonAddressBounceability.isBounceable(standard))
    }
}
