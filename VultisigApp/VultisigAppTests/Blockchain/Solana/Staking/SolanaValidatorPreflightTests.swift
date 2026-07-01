//
//  SolanaValidatorPreflightTests.swift
//  VultisigAppTests
//
//  Pins the vote-pubkey preflight: shape (base58 ed25519) + optional
//  known-vote-set membership.
//

@testable import VultisigApp
import WalletCore
import XCTest

final class SolanaValidatorPreflightTests: XCTestCase {

    private func validVotePubkey() throws -> String {
        let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0x37, count: 32)))
        return AnyAddress(publicKey: key.getPublicKeyEd25519(), coin: .solana).description
    }

    func testValidAddressPassesShapeCheck() throws {
        XCTAssertNoThrow(try SolanaValidatorPreflight.validate(try validVotePubkey()))
    }

    func testEmptyThrows() {
        XCTAssertThrowsError(try SolanaValidatorPreflight.validate("")) { error in
            XCTAssertEqual(error as? SolanaValidatorPreflight.SolanaValidatorError, .empty)
        }
    }

    func testInvalidBase58Throws() {
        // `0`, `O`, `I`, `l` are not in the base58 alphabet.
        XCTAssertThrowsError(try SolanaValidatorPreflight.validate("not_a_valid_address_0OIl")) { error in
            XCTAssertEqual(error as? SolanaValidatorPreflight.SolanaValidatorError, .invalidVotePubkey)
        }
    }

    func testKnownSetMembershipEnforcedWhenProvided() throws {
        let pubkey = try validVotePubkey()
        XCTAssertNoThrow(try SolanaValidatorPreflight.validate(pubkey, knownVotePubkeys: [pubkey]))
        XCTAssertThrowsError(
            try SolanaValidatorPreflight.validate(pubkey, knownVotePubkeys: ["SomethingElse111111111111111111111111111111"])
        ) { error in
            XCTAssertEqual(error as? SolanaValidatorPreflight.SolanaValidatorError, .unknownValidator)
        }
    }

    func testEmptyKnownSetSkipsMembership() throws {
        let pubkey = try validVotePubkey()
        XCTAssertNoThrow(try SolanaValidatorPreflight.validate(pubkey, knownVotePubkeys: []))
    }
}
