//
//  KeysignPayloadUtxoFilterTests.swift
//  VultisigAppTests
//
//  Covers `KeysignPayloadFactory.spendableUTXOs`, the filter that decides
//  which of Blockchair's rows may fund a transaction. Before this filter
//  existed the only test applied was the dust threshold, so unconfirmed
//  outputs — the ones most likely to disappear before an MPC ceremony
//  finishes — were freely selected as inputs.
//

@testable import VultisigApp
import WalletCore
import XCTest

final class KeysignPayloadUtxoFilterTests: XCTestCase {

    private static let bitcoinDust = CoinType.bitcoin.getFixedDustThreshold()

    private func makeRow(
        blockId: Int? = 900_000,
        hash: String = "aa",
        index: Int? = 0,
        value: Int? = 10_000,
        isSpendable: Bool? = nil
    ) -> Blockchair.BlockchairUtxo {
        Blockchair.BlockchairUtxo(
            blockId: blockId,
            transactionHash: hash,
            index: index,
            value: value,
            isSpendable: isSpendable
        )
    }

    private func filter(_ rows: [Blockchair.BlockchairUtxo]) -> [UtxoInfo] {
        KeysignPayloadFactory.spendableUTXOs(from: rows, dustThreshold: Self.bitcoinDust)
    }

    // MARK: - Confirmation

    /// Blockchair marks mempool outputs with `block_id == -1` and counts them
    /// in the address balance. Spending one chains onto a parent that can
    /// still be replaced or evicted, and the response carries no ancestry to
    /// tell our own change from an inbound zero-conf payment.
    func testExcludesMempoolOutputs() {
        XCTAssertTrue(filter([makeRow(blockId: -1)]).isEmpty)
    }

    func testExcludesUnconfirmedOutputsReportedAsBlockZero() {
        XCTAssertTrue(filter([makeRow(blockId: 0)]).isEmpty)
    }

    /// An output whose depth we could not establish is not spent.
    func testExcludesOutputsWithoutABlockId() {
        XCTAssertTrue(filter([makeRow(blockId: nil)]).isEmpty)
    }

    func testIncludesConfirmedOutputs() {
        let utxos = filter([makeRow(blockId: 1)])
        XCTAssertEqual(utxos.count, 1)
    }

    // MARK: - Spendability

    func testExcludesExplicitlyUnspendableOutputs() {
        XCTAssertTrue(filter([makeRow(isSpendable: false)]).isEmpty)
    }

    /// Blockchair omits `is_spendable` on Bitcoin entirely. Treating an absent
    /// field as "not spendable" would make every Bitcoin wallet unspendable.
    func testIncludesOutputsWithoutAnIsSpendableField() {
        let utxos = filter([makeRow(isSpendable: nil)])
        XCTAssertEqual(utxos.count, 1)
    }

    func testIncludesExplicitlySpendableOutputs() {
        XCTAssertEqual(filter([makeRow(isSpendable: true)]).count, 1)
    }

    // MARK: - Dust

    func testExcludesDustBelowTheChainThreshold() {
        XCTAssertTrue(filter([makeRow(value: Int(Self.bitcoinDust) - 1)]).isEmpty)
    }

    /// The threshold itself stays spendable — this pins the existing `>=`
    /// boundary so the new filter doesn't quietly tighten it.
    func testIncludesOutputsExactlyAtTheDustThreshold() {
        XCTAssertEqual(filter([makeRow(value: Int(Self.bitcoinDust))]).count, 1)
    }

    /// Dogecoin carries by far the largest threshold of the Blockchair chains,
    /// so it is the one where an off-by-one would be most visible.
    func testDustBoundaryTracksTheChainThreshold() {
        let dogeDust = CoinType.dogecoin.getFixedDustThreshold()
        XCTAssertEqual(dogeDust, 1_000_000)

        let rows = [
            makeRow(hash: "just-below", value: Int(dogeDust) - 1),
            makeRow(hash: "exactly-at", value: Int(dogeDust))
        ]

        let utxos = KeysignPayloadFactory.spendableUTXOs(from: rows, dustThreshold: dogeDust)
        XCTAssertEqual(utxos.map(\.hash), ["exactly-at"])
    }

    // MARK: - Malformed rows

    func testDropsRowsMissingTheFieldsNeededToBuildAnInput() {
        let rows = [
            makeRow(hash: ""),
            makeRow(index: nil),
            makeRow(index: -1),
            makeRow(value: nil)
        ]
        XCTAssertTrue(filter(rows).isEmpty)
    }

    /// The conversions into `UtxoInfo` are the last place a hostile or
    /// corrupted row could trap the app. They must drop, never crash.
    func testDropsRowsWhoseValueOrIndexCannotBeRepresented() {
        let rows = [
            makeRow(hash: "negative-value", value: -1),
            makeRow(hash: "index-past-uint32", index: Int(UInt32.max) + 1)
        ]
        XCTAssertTrue(filter(rows).isEmpty)
    }

    /// The widest vout an output can legitimately carry still maps through.
    func testKeepsTheLargestRepresentableIndex() {
        let utxos = filter([makeRow(hash: "wide", index: Int(UInt32.max))])
        XCTAssertEqual(utxos.map(\.index), [UInt32.max])
    }

    // MARK: - Mapping

    func testMapsSurvivingRowsPreservingOrderAndFields() {
        let rows = [
            makeRow(blockId: 900_001, hash: "first", index: 2, value: 50_000),
            makeRow(blockId: -1, hash: "unconfirmed", index: 0, value: 90_000),
            makeRow(blockId: 900_002, hash: "second", index: 0, value: 700, isSpendable: true),
            makeRow(blockId: 900_003, hash: "unspendable", index: 1, value: 80_000, isSpendable: false),
            makeRow(blockId: 900_004, hash: "dust", index: 0, value: 100)
        ]

        let utxos = filter(rows)

        XCTAssertEqual(utxos.map(\.hash), ["first", "second"])
        XCTAssertEqual(utxos.map(\.amount), [50_000, 700])
        XCTAssertEqual(utxos.map(\.index), [2, 0])
    }

    /// A realistic snapshot: the wallet holds a confirmed balance plus a
    /// freshly-broadcast change output. Only the confirmed part is offered to
    /// the planner, so a chained spend waits for confirmation instead of
    /// building a transaction whose parent might still be replaced.
    func testUnconfirmedChangeIsWithheldFromTheCandidateSet() {
        let rows = [
            makeRow(blockId: -1, hash: "pending-change", index: 1, value: 3_000_000),
            makeRow(blockId: 899_999, hash: "confirmed", index: 0, value: 1_000_000)
        ]

        let utxos = filter(rows)

        XCTAssertEqual(utxos.map(\.hash), ["confirmed"])
        XCTAssertEqual(utxos.map(\.amount).reduce(0, +), 1_000_000)
    }
}
