//
//  KeyshareProtectorTests.swift
//  VultisigAppTests
//

import CryptoKit
import XCTest
@testable import VultisigApp

final class KeyshareProtectorTests: XCTestCase {

    private let dklsPlaintext = "eyJrZXlzaGFyZSI6ImV4YW1wbGUifQ=="
    private let gg20Plaintext = #"{"PubKey":"02abc","ShareID":{"value":"12345"}}"#

    private func makeProtector(_ state: @escaping @autoclosure () -> KeyshareProtectionState) -> KeyshareProtector {
        KeyshareProtector(state: state)
    }

    private func makeUnlockedProtector() throws -> KeyshareProtector {
        let key = try VaultCryptoEnvelope.randomKey()
        return KeyshareProtector(state: { .unlocked(key) })
    }

    // MARK: - Disabled — the state this PR ships in

    func testDisabledSealIsAPassthrough() throws {
        let sut = makeProtector(.disabled)

        XCTAssertEqual(try sut.seal(dklsPlaintext), dklsPlaintext)
        XCTAssertEqual(try sut.seal(gg20Plaintext), gg20Plaintext)
    }

    func testDisabledOpenIsAPassthrough() throws {
        let sut = makeProtector(.disabled)

        XCTAssertEqual(try sut.open(dklsPlaintext), dklsPlaintext)
        XCTAssertEqual(try sut.open(gg20Plaintext), gg20Plaintext)
    }

    func testDisabledRoundTripLeavesTheValueByteIdentical() throws {
        let sut = makeProtector(.disabled)

        let stored = try sut.seal(dklsPlaintext)

        XCTAssertEqual(stored, dklsPlaintext)
        XCTAssertEqual(try sut.open(stored), dklsPlaintext)
    }

    // MARK: - Unlocked

    func testUnlockedSealThenOpenRoundTrips() throws {
        let sut = try makeUnlockedProtector()

        let stored = try sut.seal(dklsPlaintext)

        XCTAssertNotEqual(stored, dklsPlaintext)
        XCTAssertEqual(try sut.open(stored), dklsPlaintext)
    }

    func testUnlockedOpenStillAcceptsPlaintext() throws {
        let sut = try makeUnlockedProtector()

        // A store part-way through a sweep holds both forms, so a plaintext
        // share has to stay readable while the key is already in hand.
        XCTAssertEqual(try sut.open(dklsPlaintext), dklsPlaintext)
    }

    func testUnlockedSealDoesNotDoubleSeal() throws {
        let sut = try makeUnlockedProtector()
        let stored = try sut.seal(dklsPlaintext)

        let resealed = try sut.seal(stored)

        XCTAssertEqual(resealed, stored, "Re-sealing must be idempotent so a sweep can retry")
        XCTAssertEqual(try sut.open(resealed), dklsPlaintext)
    }

    func testUnlockedOpenWithADifferentKeyFails() throws {
        let sealed = try makeUnlockedProtector().seal(dklsPlaintext)
        let other = try makeUnlockedProtector()

        XCTAssertThrowsError(try other.open(sealed)) { error in
            XCTAssertEqual(error as? KeyshareProtectionError, .cipherFailure)
        }
    }

    // MARK: - Locked

    func testLockedOpenOfASealedShareThrows() throws {
        let sealed = try makeUnlockedProtector().seal(dklsPlaintext)
        let sut = makeProtector(.locked)

        XCTAssertThrowsError(try sut.open(sealed)) { error in
            XCTAssertEqual(error as? KeyshareProtectionError, .locked)
        }
    }

    func testLockedOpenOfAPlaintextShareStillWorks() throws {
        let sut = makeProtector(.locked)

        XCTAssertEqual(try sut.open(dklsPlaintext), dklsPlaintext)
    }

    func testLockedSealThrows() {
        let sut = makeProtector(.locked)

        XCTAssertThrowsError(try sut.seal(dklsPlaintext)) { error in
            XCTAssertEqual(error as? KeyshareProtectionError, .locked)
        }
    }

    /// Never hand ciphertext back as if it were a share: the TSS layer would
    /// read it as a corrupt key share rather than as a locked app.
    func testDisabledOpenOfASealedShareThrowsRatherThanReturningCiphertext() throws {
        let sealed = try makeUnlockedProtector().seal(dklsPlaintext)
        let sut = makeProtector(.disabled)

        XCTAssertThrowsError(try sut.open(sealed)) { error in
            XCTAssertEqual(error as? KeyshareProtectionError, .locked)
        }
    }
}
