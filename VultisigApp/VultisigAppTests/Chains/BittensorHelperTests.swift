//
//  BittensorHelperTests.swift
//  VultisigApp
//
//  Pins BittensorHelper's SS58 decode as the single strict parser the form
//  (`isValidAddress`) and the sign path (`buildCallData`, via
//  `getPreSignedImageHash`/`getSignedTransaction`) share: prefix 42 + a valid
//  checksum + an exact byte length, or the address is rejected outright —
//  never a byte offset carved out of an unvalidated string.
//

@testable import VultisigApp
import BigInt
import Tss
import WalletCore
import XCTest

final class BittensorHelperTests: XCTestCase {

    // MARK: - Fixtures (mirrors TestData/bittensor.json)

    /// Real, checksummed SS58-42 Bittensor address.
    private let validAddress = "5DtJMgqtYZg6NyCM1KDkmgZ6nW7pKgL1fneDHQtwPjBrQuXG"
    /// The 32-byte ed25519 public key `validAddress` encodes.
    private let validAddressPubKeyHex = "5088e7e9faef052bbf655fe91f9a9effb421d4fd68a1597645918803d84c660c"

    /// Same 32-byte public key as `validAddress`, but SS58-encoded with the
    /// Polkadot mainnet prefix (0) instead of Bittensor's (42) — a real,
    /// checksummed, otherwise-valid Substrate address on the wrong network.
    private let polkadotPrefixAddress = "12pbW26xQLwZpWCrxxGkuqPFe87U1yt9kHNhShtHwpDNb5Tp"

    /// `validAddress` with the final checksum byte flipped, re-encoded.
    private let checksumCorruptedAddress = "5DtJMgqtYZg6NyCM1KDkmgZ6nW7pKgL1fneDHQtwPjBrQuWb"

    /// `validAddress`'s decoded bytes (prefix + pubkey + checksum) with one
    /// extra trailing byte appended before re-encoding: the checksum still
    /// verifies against the leading 33 bytes, but the payload is 36 bytes
    /// instead of the 35 a single-byte prefix requires.
    private let trailingGarbageAddress = "KdsRcJrnWKDYjy35JPRJCDagXqX5sSauxCTFDSUF5KCu6WpcA"

    /// Same public key + second byte as the canonical two-byte encoding of
    /// prefix 42, but with first byte 0x8A (138) instead of the canonical
    /// 0x4A (74) — SS58's two-byte prefix indicator is 64...127, so 138 is
    /// reserved, not a valid prefix byte at all. The prefix-decode formula
    /// only reads the low 6 bits of the first byte, so without an explicit
    /// upper bound this reserved byte aliases onto prefix 42 anyway, with a
    /// checksum that verifies (it's computed over these exact bytes).
    private let malformedTwoBytePrefixAddress = "23zq2QKhC35xn5Vjvca3cuJYonkEMHz1EmqhZy8xRcjWr74t8y"

    // MARK: - ss58Decode

    func testSs58DecodeValidAddressReturnsExpectedPublicKey() throws {
        let decoded = try XCTUnwrap(BittensorHelper.ss58Decode(validAddress))
        XCTAssertEqual(decoded, try XCTUnwrap(Data(hexString: validAddressPubKeyHex)))
    }

    func testSs58DecodeRejectsPrefixZeroPolkadotAddress() {
        XCTAssertNil(BittensorHelper.ss58Decode(polkadotPrefixAddress))
    }

    func testSs58DecodeRejectsChecksumCorruption() {
        XCTAssertNil(BittensorHelper.ss58Decode(checksumCorruptedAddress))
    }

    func testSs58DecodeRejectsTrailingGarbageAfterChecksum() {
        XCTAssertNil(BittensorHelper.ss58Decode(trailingGarbageAddress))
    }

    func testSs58DecodeRejectsReservedTwoBytePrefixByte() {
        XCTAssertNil(BittensorHelper.ss58Decode(malformedTwoBytePrefixAddress))
    }

    // MARK: - isValidAddress (must agree with ss58Decode)

    func testIsValidAddressAcceptsRealBittensorAddress() {
        XCTAssertTrue(BittensorHelper.isValidAddress(validAddress))
    }

    func testIsValidAddressRejectsPrefixZeroPolkadotAddress() {
        XCTAssertFalse(BittensorHelper.isValidAddress(polkadotPrefixAddress))
    }

    func testIsValidAddressRejectsChecksumCorruption() {
        XCTAssertFalse(BittensorHelper.isValidAddress(checksumCorruptedAddress))
    }

    // MARK: - Sign path: same rejections must throw, never silently sign

    func testGetPreSignedImageHashThrowsForPrefixZeroAddress() throws {
        let payload = try makePayload(toAddress: polkadotPrefixAddress)
        assertThrowsInvalidDestinationAddress(try BittensorHelper.getPreSignedImageHash(keysignPayload: payload))
    }

    func testGetPreSignedImageHashThrowsForChecksumCorruptedAddress() throws {
        let payload = try makePayload(toAddress: checksumCorruptedAddress)
        assertThrowsInvalidDestinationAddress(try BittensorHelper.getPreSignedImageHash(keysignPayload: payload))
    }

    func testGetSignedTransactionThrowsForPrefixZeroAddress() throws {
        let payload = try makePayload(toAddress: polkadotPrefixAddress)
        assertThrowsInvalidDestinationAddress(try BittensorHelper.getSignedTransaction(keysignPayload: payload, signatures: [:]))
    }

    func testGetSignedTransactionThrowsForChecksumCorruptedAddress() throws {
        let payload = try makePayload(toAddress: checksumCorruptedAddress)
        assertThrowsInvalidDestinationAddress(try BittensorHelper.getSignedTransaction(keysignPayload: payload, signatures: [:]))
    }

    func testGetPreSignedImageHashSucceedsForValidAddress() throws {
        let payload = try makePayload(toAddress: validAddress)
        XCTAssertNoThrow(try BittensorHelper.getPreSignedImageHash(keysignPayload: payload))
    }

    // MARK: - Fixtures

    /// Asserts the expression throws specifically `buildCallData`'s rejection,
    /// not merely "some error" — an unrelated downstream throw (e.g. signature
    /// verification failing on empty test signatures) would let a regression
    /// that silently accepts an invalid address pass this test for the wrong
    /// reason.
    private func assertThrowsInvalidDestinationAddress<T>(
        _ expression: @autoclosure () throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            guard case HelperError.runtimeError(let message) = error else {
                XCTFail("expected HelperError.runtimeError, got \(error)", file: file, line: line)
                return
            }
            XCTAssertEqual(message, "Invalid Bittensor destination address", file: file, line: line)
        }
    }

    private func makePayload(toAddress: String) throws -> KeysignPayload {
        let coin = SigningGoldenFactory.coin(chain: .bittensor, ticker: "TAO", decimals: 9, curve: .ed25519)
        return SigningGoldenFactory.payload(
            coin: coin,
            toAddress: toAddress,
            toAmount: BigInt(1_000_000_000),
            chainSpecific: .Polkadot(
                recentBlockHash: Self.polkadotGenesis,
                nonce: 0,
                currentBlockNumber: BigInt(5_234_567),
                specVersion: 260,
                transactionVersion: 5,
                genesisHash: Self.polkadotGenesis
            )
        )
    }

    private static let polkadotGenesis = "91b171bb158e2d3848fa23a9f1c25182fb8e20313b2c1eb49219da7a70ce90c3"
}
