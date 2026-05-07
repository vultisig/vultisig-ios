//
//  CardanoExtendedUtxoTests.swift
//  VultisigApp
//

@testable import VultisigApp
import BigInt
import XCTest

final class CardanoExtendedUtxoTests: XCTestCase {

    // MARK: - Mapping

    func testMapsAdaOnlyEntry() throws {
        let entry = CardanoExtendedUtxoEntry(
            txHash: "abc",
            txIndex: 0,
            value: "5000000",
            assetList: []
        )
        let utxo = try XCTUnwrap(CardanoExtendedUtxo(entry))
        XCTAssertEqual(utxo.hash, "abc")
        XCTAssertEqual(utxo.index, 0)
        XCTAssertEqual(utxo.amount, 5_000_000)
        XCTAssertTrue(utxo.assets.isEmpty)
        XCTAssertFalse(utxo.hasAssets)
    }

    func testMapsCNTBearingEntryAndLowercasesAssetIds() throws {
        let entry = CardanoExtendedUtxoEntry(
            txHash: "def",
            txIndex: 1,
            value: "1500000",
            assetList: [
                CardanoAssetEntry(
                    policyId: "ABC123",
                    assetName: "DEAD",
                    fingerprint: "asset1xyz",
                    decimals: 6,
                    quantity: "42"
                )
            ]
        )
        let utxo = try XCTUnwrap(CardanoExtendedUtxo(entry))
        XCTAssertTrue(utxo.hasAssets)
        XCTAssertEqual(utxo.assets.count, 1)
        let asset = utxo.assets[0]
        XCTAssertEqual(asset.policyId, "abc123")
        XCTAssertEqual(asset.assetNameHex, "dead")
        XCTAssertEqual(asset.amount, BigInt(42))
        XCTAssertEqual(asset.decimals, 6)
    }

    func testMapsNullAssetListAsEmpty() throws {
        let entry = CardanoExtendedUtxoEntry(
            txHash: "1",
            txIndex: 0,
            value: "1000000",
            assetList: nil
        )
        let utxo = try XCTUnwrap(CardanoExtendedUtxo(entry))
        XCTAssertTrue(utxo.assets.isEmpty)
    }

    func testMapsNullAssetNameAndDecimalsAsDefaults() throws {
        let entry = CardanoExtendedUtxoEntry(
            txHash: "2",
            txIndex: 0,
            value: "1000000",
            assetList: [
                CardanoAssetEntry(policyId: "abc", assetName: nil, fingerprint: nil, decimals: nil, quantity: "1")
            ]
        )
        let utxo = try XCTUnwrap(CardanoExtendedUtxo(entry))
        XCTAssertEqual(utxo.assets[0].assetNameHex, "")
        XCTAssertEqual(utxo.assets[0].decimals, 0)
    }

    func testRejectsEmptyTxHash() {
        let entry = CardanoExtendedUtxoEntry(txHash: "", txIndex: 0, value: "1", assetList: nil)
        XCTAssertNil(CardanoExtendedUtxo(entry))
    }

    func testRejectsNegativeIndex() {
        let entry = CardanoExtendedUtxoEntry(txHash: "x", txIndex: -1, value: "1", assetList: nil)
        XCTAssertNil(CardanoExtendedUtxo(entry))
    }

    func testRejectsNonNumericValue() {
        let entry = CardanoExtendedUtxoEntry(txHash: "x", txIndex: 0, value: "not-a-number", assetList: nil)
        XCTAssertNil(CardanoExtendedUtxo(entry))
    }

    func testSkipsAssetsWithNonNumericQuantity() throws {
        let entry = CardanoExtendedUtxoEntry(
            txHash: "x",
            txIndex: 0,
            value: "1000000",
            assetList: [
                CardanoAssetEntry(policyId: "a", assetName: "b", fingerprint: nil, decimals: 0, quantity: "garbage"),
                CardanoAssetEntry(policyId: "c", assetName: "d", fingerprint: nil, decimals: 0, quantity: "5")
            ]
        )
        let utxo = try XCTUnwrap(CardanoExtendedUtxo(entry))
        XCTAssertEqual(utxo.assets.count, 1)
        XCTAssertEqual(utxo.assets[0].policyId, "c")
    }

    // MARK: - Koios JSON wire decoding

    func testDecodesKoiosResponseWithAssets() throws {
        let json = #"""
        [
          {
            "tx_hash": "11",
            "tx_index": 0,
            "value": "5000000",
            "asset_list": [
              {
                "policy_id": "ABCD",
                "asset_name": "DEAD",
                "fingerprint": "asset1xyz",
                "decimals": 6,
                "quantity": "42"
              }
            ]
          },
          {
            "tx_hash": "22",
            "tx_index": 1,
            "value": "2000000",
            "asset_list": null
          }
        ]
        """#
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([CardanoExtendedUtxoEntry].self, from: data)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].assetList?.count, 1)
        XCTAssertEqual(decoded[0].assetList?[0].policyId, "ABCD")
        XCTAssertEqual(decoded[0].assetList?[0].quantity, "42")
        XCTAssertNil(decoded[1].assetList)
    }
}
