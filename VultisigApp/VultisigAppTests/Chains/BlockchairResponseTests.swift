//
//  BlockchairResponseTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

/// Regression coverage for the v1.36.51+ BTC send failure (issue #4306).
///
/// `BlockchairUtxo.transactionHash` decodes from the wire field
/// `transaction_hash`. Before the HTTPClient migration the service used a
/// custom `JSONDecoder` with `.convertFromSnakeCase`, which masked the
/// missing `CodingKeys`. The migrated `HTTPClient` uses a vanilla
/// `JSONDecoder`, so without explicit keys every UTXO decoded with a `nil`
/// `transactionHash` and was dropped by `KeysignPayloadFactory.selectUTXOs`,
/// preventing BTC sends.
final class BlockchairResponseTests: XCTestCase {

    /// Real Blockchair-shaped payload so the test pins the wire contract,
    /// not just the field renaming.
    private let payload: Data = {
        let json = """
        {
            "data": {
                "bc1qexampleaddress0000000000000000000000": {
                    "address": {
                        "type": null,
                        "script_hex": "0014a1b2",
                        "balance": 250000,
                        "unspent_output_count": 2
                    },
                    "utxo": [
                        {
                            "block_id": 800000,
                            "transaction_hash": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                            "index": 0,
                            "value": 100000
                        },
                        {
                            "block_id": 800001,
                            "transaction_hash": "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210",
                            "index": 1,
                            "value": 150000
                        }
                    ]
                }
            }
        }
        """
        return Data(json.utf8)
    }()

    func test_blockchairUtxoDecodes_transactionHash_fromSnakeCase() throws {
        // Mirrors the decoder configuration `HTTPClient` uses by default —
        // no key strategy, no special handling. The fix lives in the model.
        let response = try JSONDecoder().decode(BlockchairResponse.self, from: payload)

        let entry = try XCTUnwrap(response.data["bc1qexampleaddress0000000000000000000000"])
        let utxos = try XCTUnwrap(entry.utxo)

        XCTAssertEqual(utxos.count, 2)
        XCTAssertEqual(utxos[0].transactionHash, "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
        XCTAssertEqual(utxos[0].index, 0)
        XCTAssertEqual(utxos[0].value, 100000)
        XCTAssertEqual(utxos[1].transactionHash, "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210")
        XCTAssertEqual(entry.address?.balance, 250000)
    }

    /// `unspent_output_count` is the only signal that Blockchair truncated the
    /// `utxo` array to the request's `limit`. It has to decode, or pagination
    /// has nothing to terminate against.
    func testBlockchairAddressDecodesUnspentOutputCountAndScriptHex() throws {
        let response = try JSONDecoder().decode(BlockchairResponse.self, from: payload)

        let entry = try XCTUnwrap(response.data["bc1qexampleaddress0000000000000000000000"])
        let address = try XCTUnwrap(entry.address)

        XCTAssertEqual(address.unspentOutputCount, 2)
        XCTAssertEqual(address.scriptHex, "0014a1b2")
    }

    /// Blockchair's Bitcoin responses omit `is_spendable` entirely, so the
    /// field decodes to `nil` and callers must read that as "spendable".
    /// Chains that do send it must round-trip both boolean values.
    func testBlockchairUtxoDecodesIsSpendableAsOptional() throws {
        let json = """
        {
            "data": {
                "addr": {
                    "utxo": [
                        { "block_id": 1, "transaction_hash": "a", "index": 0, "value": 10 },
                        { "block_id": 2, "transaction_hash": "b", "index": 0, "value": 20, "is_spendable": false },
                        { "block_id": 3, "transaction_hash": "c", "index": 0, "value": 30, "is_spendable": true },
                        { "block_id": 4, "transaction_hash": "d", "index": 0, "value": 40, "is_spendable": null }
                    ]
                }
            }
        }
        """
        let response = try JSONDecoder().decode(BlockchairResponse.self, from: Data(json.utf8))
        let utxos = try XCTUnwrap(response.data["addr"]?.utxo)

        XCTAssertEqual(utxos.count, 4)
        XCTAssertNil(utxos[0].isSpendable, "absent is_spendable must stay nil, not default to false")
        XCTAssertEqual(utxos[1].isSpendable, false)
        XCTAssertEqual(utxos[2].isSpendable, true)
        XCTAssertNil(utxos[3].isSpendable, "explicit null must decode like an absent field")
    }

    /// The `address` object is optional on this endpoint and older/partial
    /// payloads omit `unspent_output_count`. Neither may break decoding —
    /// pagination treats an absent count as "no total reported".
    func testBlockchairDecodesWithoutAddressObjectOrUnspentOutputCount() throws {
        let json = """
        { "data": { "addr": { "address": { "balance": 1 }, "utxo": [] } } }
        """
        let response = try JSONDecoder().decode(BlockchairResponse.self, from: Data(json.utf8))

        let entry = try XCTUnwrap(response.data["addr"])
        XCTAssertEqual(entry.address?.balance, 1)
        XCTAssertNil(entry.address?.unspentOutputCount)
        XCTAssertNil(entry.address?.scriptHex)
    }
}
