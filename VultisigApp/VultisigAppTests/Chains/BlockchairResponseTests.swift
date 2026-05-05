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
                        "script_hex": "",
                        "balance": 250000
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
}
