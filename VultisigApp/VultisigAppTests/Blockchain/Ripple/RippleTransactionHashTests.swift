//
//  RippleTransactionHashTests.swift
//  VultisigAppTests
//
//  Pins the deterministic XRPL transaction identifying hash that
//  `RippleHelper.signedTransactionHash(signedBlob:)` computes for a signed XRP
//  transaction: SHA-512Half of the 4-byte `TXN\0` prefix (0x54584E00) + the
//  serialized signed blob, rendered as uppercase hex.
//
//  The fixtures are real mainnet transactions pulled from ledger 105416247 via
//  the `tx` JSON-RPC method (`binary: true`) against a public XRPL endpoint. The
//  expected value is each transaction's own on-chain hash — the canonical proof
//  that the local computation reproduces exactly what the ledger assigns. The
//  blob + expected hash are baked as constants so the tests run fully offline.
//
//  - https://xrpl.org/docs/references/protocol/data-types/hash-prefixes
//  - https://xrpl.org/docs/concepts/transactions/finality-of-results
//

@testable import VultisigApp
import XCTest
import WalletCore

final class RippleTransactionHashTests: XCTestCase {

    // Real mainnet Payment (secp256k1-signed), ledger 105416247.
    private let paymentBlobHex = "12000023000000DE2405F45C49614000000000000F5868400000000000000F7321026180E1CD4F966CF2BDC947F177F41CC4D7E61265CD7DEE297C098FEFC05FEDA37446304402203353A6C6EDAB6EC54B37F474570192DEC0F969B3EE528B7E5C7551807ED41FB802207DCC77F89A60D8D2C90B1AB5B89EB76A0F8C64D930F015A755FB84F637C29ACC8114E4792E06D3A514EE266E4AF5CB3795AABBE1F49D831408EF73DE114C04A3408837BF2399D1A8458A0204F9EA7D13486F72697A6F6E20426F6F7374657220466565E1F1"
    private let paymentExpectedHash = "00D3BAABAE790E1B9F772172CB5AD486161294E7F25916CC4E52423227768A14"

    // Real mainnet OfferCreate (ed25519-signed), ledger 105416247. Proves the
    // hash is agnostic to transaction type / signature scheme — it is a pure
    // digest of the serialized signed bytes.
    private let offerBlobHex = "1200072200010000240617B1A020190617B19F64400000000005B7B165D44F491087F5D800524C555344000000000000000000000000000000E5E961C6A025C9404AA7B662DD1DF975BE75D13E68400000000000000C7321ED1A8CA8C2249E7695955D8B17CB3250A7DA40B6A70D5532ECF7712188642CBEBD7440A782A072DBCDF20173C2BD08CAC2BCE1C147C298C8FB19C7F0167F4D6FF0A6F00B48B2FC5E5DBA2455E532ED2DF61830ED66BE91642F081E248767478ED3A4088114DEF23F96A90D53B409ACC5F68A634A53E13D4FFD"
    private let offerExpectedHash = "06E809490BE5C3341F9F11ED2067F168094E0BCD7AE047D37334113FE559D732"

    func testMainnetPaymentBlobMatchesOnChainHash() throws {
        let blob = try XCTUnwrap(Data(hexString: paymentBlobHex))
        let hash = RippleHelper.signedTransactionHash(signedBlob: blob)
        XCTAssertEqual(hash, paymentExpectedHash)
    }

    func testMainnetOfferCreateBlobMatchesOnChainHash() throws {
        let blob = try XCTUnwrap(Data(hexString: offerBlobHex))
        let hash = RippleHelper.signedTransactionHash(signedBlob: blob)
        XCTAssertEqual(hash, offerExpectedHash)
    }

    func testHashIsUppercaseHex() throws {
        let blob = try XCTUnwrap(Data(hexString: paymentBlobHex))
        let hash = RippleHelper.signedTransactionHash(signedBlob: blob)
        XCTAssertEqual(hash, hash.uppercased())
        let hexCharacters = CharacterSet(charactersIn: "0123456789ABCDEF")
        XCTAssertTrue(
            hash.unicodeScalars.allSatisfy { hexCharacters.contains($0) },
            "hash must be uppercase hex only"
        )
    }

    func testHashLengthIs64Characters() throws {
        // SHA-512Half is 32 bytes → 64 hex characters.
        let blob = try XCTUnwrap(Data(hexString: offerBlobHex))
        let hash = RippleHelper.signedTransactionHash(signedBlob: blob)
        XCTAssertEqual(hash.count, 64)
    }

    func testEmptyBlobReturnsEmptyString() {
        // An empty blob must yield an empty hash so the hash-keyed keysign
        // safety nets stay disarmed rather than keying off a prefix-only digest.
        XCTAssertEqual(RippleHelper.signedTransactionHash(signedBlob: Data()), "")
    }

    func testHashIsDeterministic() throws {
        let blob = try XCTUnwrap(Data(hexString: paymentBlobHex))
        let first = RippleHelper.signedTransactionHash(signedBlob: blob)
        let second = RippleHelper.signedTransactionHash(signedBlob: blob)
        XCTAssertEqual(first, second)
    }

    func testSingleByteDifferenceChangesHash() throws {
        var mutated = try XCTUnwrap(Data(hexString: paymentBlobHex))
        mutated[mutated.startIndex] ^= 0xFF
        let hash = RippleHelper.signedTransactionHash(signedBlob: mutated)
        XCTAssertNotEqual(hash, paymentExpectedHash)
        XCTAssertEqual(hash.count, 64)
    }
}
