//
//  QBTCClaimableUtxosTests.swift
//  VultisigAppTests
//
//  Tests for the Blockchair → ClaimableUtxo mapping.
//

@testable import VultisigApp
import XCTest

final class QBTCClaimableUtxosTests: XCTestCase {
    func testInitFromValidBlockchairUtxo() throws {
        let raw = Blockchair.BlockchairUtxo(
            transactionHash: String(repeating: "aa", count: 32),
            index: 3,
            value: 100_000
        )
        let utxo = try XCTUnwrap(ClaimableUtxo(blockchair: raw))
        XCTAssertEqual(utxo.txid, raw.transactionHash)
        XCTAssertEqual(utxo.vout, 3)
        XCTAssertEqual(utxo.amount, 100_000)
    }

    func testInitFromVoutZeroBlockchairUtxo() throws {
        let raw = Blockchair.BlockchairUtxo(
            transactionHash: String(repeating: "bb", count: 32),
            index: 0,
            value: 1
        )
        let utxo = try XCTUnwrap(ClaimableUtxo(blockchair: raw))
        XCTAssertEqual(utxo.vout, 0)
    }

    func testInitReturnsNilWhenTxidIsMissing() {
        let raw = Blockchair.BlockchairUtxo(transactionHash: nil, index: 1, value: 100)
        XCTAssertNil(ClaimableUtxo(blockchair: raw))
    }

    func testInitReturnsNilWhenTxidIsEmpty() {
        let raw = Blockchair.BlockchairUtxo(transactionHash: "", index: 1, value: 100)
        XCTAssertNil(ClaimableUtxo(blockchair: raw))
    }

    func testInitReturnsNilWhenIndexIsMissing() {
        let raw = Blockchair.BlockchairUtxo(
            transactionHash: String(repeating: "aa", count: 32),
            index: nil,
            value: 100
        )
        XCTAssertNil(ClaimableUtxo(blockchair: raw))
    }

    func testInitReturnsNilWhenIndexIsNegative() {
        let raw = Blockchair.BlockchairUtxo(
            transactionHash: String(repeating: "aa", count: 32),
            index: -1,
            value: 100
        )
        XCTAssertNil(ClaimableUtxo(blockchair: raw))
    }

    func testInitReturnsNilWhenValueIsMissing() {
        let raw = Blockchair.BlockchairUtxo(
            transactionHash: String(repeating: "aa", count: 32),
            index: 0,
            value: nil
        )
        XCTAssertNil(ClaimableUtxo(blockchair: raw))
    }

    func testInitReturnsNilWhenValueIsNegative() {
        let raw = Blockchair.BlockchairUtxo(
            transactionHash: String(repeating: "aa", count: 32),
            index: 0,
            value: -1
        )
        XCTAssertNil(ClaimableUtxo(blockchair: raw))
    }

    func testCompactMapSkipsMalformedEntries() {
        let raws: [Blockchair.BlockchairUtxo] = [
            .init(transactionHash: String(repeating: "aa", count: 32), index: 0, value: 100),
            .init(transactionHash: nil, index: 1, value: 200), // dropped: missing txid
            .init(transactionHash: String(repeating: "bb", count: 32), index: 1, value: 300),
            .init(transactionHash: String(repeating: "cc", count: 32), index: -1, value: 400) // dropped: bad index
        ]
        let mapped = raws.compactMap(ClaimableUtxo.init(blockchair:))
        XCTAssertEqual(mapped.count, 2)
        XCTAssertEqual(mapped[0].amount, 100)
        XCTAssertEqual(mapped[1].amount, 300)
    }
}
