//
//  SolanaAddressLookupTableTests.swift
//  VultisigAppTests
//
//  A v0 transaction names most of its accounts by position inside a lookup
//  table, so these bytes decide which account every one of those indices refers
//  to. A decode that is off by a field, or that trusts an account the lookup
//  table program does not own, renames accounts silently — and the app then
//  validates a transaction it has misread.
//

@testable import VultisigApp
import WalletCore
import XCTest

final class SolanaAddressLookupTableTests: XCTestCase {

    private static let tableAddress = "9p2oT9J6BojHigd3V5qXzrwsQf4dtgMgLxtrzLVR3rwu"

    // MARK: - Decoding

    func testDecodesTheAddressListAfterTheMetadata() throws {
        let addresses = [
            "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
            "11111111111111111111111111111111"
        ]

        let decoded = try SolanaAddressLookupTable.addresses(
            table: Self.tableAddress,
            accountData: Self.account(addresses: addresses)
        )

        XCTAssertEqual(decoded, addresses)
    }

    func testDecodesAnEmptyTable() throws {
        let decoded = try SolanaAddressLookupTable.addresses(
            table: Self.tableAddress,
            accountData: Self.account(addresses: [])
        )
        XCTAssertEqual(decoded, [])
    }

    /// The whole point of the fixed 56-byte prefix: the first address starts
    /// there, not at the start of the account. Decoding from the wrong offset
    /// yields addresses that are all plausible base58 and all wrong.
    func testFirstAddressStartsAtTheMetadataBoundary() throws {
        let mint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
        var data = Self.account(addresses: [mint])
        // Fill the metadata with a recognisable pattern; the decode must ignore
        // every byte of it except the discriminant.
        for index in 4..<SolanaAddressLookupTable.metadataSize { data[index] = 0xAB }

        let decoded = try SolanaAddressLookupTable.addresses(table: Self.tableAddress, accountData: data)
        XCTAssertEqual(decoded, [mint])
    }

    // MARK: - Guards

    func testRejectsAnAccountOwnedByAnotherProgram() throws {
        XCTAssertThrowsError(
            try SolanaAddressLookupTable.addresses(
                table: Self.tableAddress,
                owner: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
                data: [Data(Self.account(addresses: [])).base64EncodedString(), "base64"]
            )
        ) { error in
            XCTAssertEqual(
                error as? SolanaAddressLookupTableError,
                .wrongOwner(table: Self.tableAddress, owner: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
            )
        }
    }

    /// `jsonParsed` would hand the decode to the RPC node. Asserting the encoding
    /// the node reports keeps that from happening silently.
    func testRejectsANonBase64Encoding() throws {
        XCTAssertThrowsError(
            try SolanaAddressLookupTable.addresses(
                table: Self.tableAddress,
                owner: SolanaAddressLookupTable.programId,
                data: ["{}", "jsonParsed"]
            )
        ) { error in
            XCTAssertEqual(error as? SolanaAddressLookupTableError, .unsupportedEncoding(table: Self.tableAddress))
        }
    }

    func testRejectsAnUninitializedTable() throws {
        var data = Self.account(addresses: [])
        data[0] = 0

        XCTAssertThrowsError(
            try SolanaAddressLookupTable.addresses(table: Self.tableAddress, accountData: data)
        ) { error in
            XCTAssertEqual(error as? SolanaAddressLookupTableError, .uninitialized(table: Self.tableAddress))
        }
    }

    func testRejectsAnAccountShorterThanItsMetadata() throws {
        XCTAssertThrowsError(
            try SolanaAddressLookupTable.addresses(
                table: Self.tableAddress,
                accountData: [UInt8](repeating: 0, count: SolanaAddressLookupTable.metadataSize - 1)
            )
        ) { error in
            XCTAssertEqual(error as? SolanaAddressLookupTableError, .malformedAccountData(table: Self.tableAddress))
        }
    }

    /// A trailing partial key means the address list was read at the wrong
    /// offset. Every address after that point would be shifted rather than
    /// obviously invalid, so this has to be a refusal rather than a truncation.
    func testRejectsATrailingPartialAddress() throws {
        var data = Self.account(addresses: ["EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"])
        data += [0x01, 0x02, 0x03]

        XCTAssertThrowsError(
            try SolanaAddressLookupTable.addresses(table: Self.tableAddress, accountData: data)
        ) { error in
            XCTAssertEqual(error as? SolanaAddressLookupTableError, .malformedAccountData(table: Self.tableAddress))
        }
    }

    func testRejectsMalformedBase64Payload() throws {
        XCTAssertThrowsError(
            try SolanaAddressLookupTable.addresses(
                table: Self.tableAddress,
                owner: SolanaAddressLookupTable.programId,
                data: ["not base64 !!", "base64"]
            )
        ) { error in
            XCTAssertEqual(error as? SolanaAddressLookupTableError, .unsupportedEncoding(table: Self.tableAddress))
        }
    }

    // MARK: - Fixture

    /// A `ProgramState::LookupTable` account: the 4-byte bincode discriminant,
    /// 52 further bytes of `LookupTableMeta`, then the packed 32-byte addresses.
    private static func account(addresses: [String]) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: SolanaAddressLookupTable.metadataSize)
        data[0] = UInt8(SolanaAddressLookupTable.lookupTableDiscriminant)
        for address in addresses {
            guard let decoded = Base58.decodeNoCheck(string: address), decoded.count == 32 else {
                XCTFail("fixture address \(address) is not 32 bytes")
                return data
            }
            data += [UInt8](decoded)
        }
        return data
    }
}
