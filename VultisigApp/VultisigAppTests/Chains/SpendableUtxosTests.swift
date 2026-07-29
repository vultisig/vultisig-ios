//
//  SpendableUtxosTests.swift
//  VultisigAppTests
//
//  Covers `SpendableUtxos`, the one predicate that decides which of
//  Blockchair's rows this wallet counts as its own money — for the balance on
//  screen and for the inputs a transaction is funded from alike. Before it
//  existed the only filter applied to the candidate set was the dust
//  threshold, so unconfirmed outputs a stranger could still replace were
//  freely selected as inputs.
//

@testable import VultisigApp
import BigInt
import WalletCore
import XCTest

final class SpendableUtxosTests: XCTestCase {

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

    private func filter(
        _ rows: [Blockchair.BlockchairUtxo],
        own: Set<String> = []
    ) -> [UtxoInfo] {
        SpendableUtxos.select(
            from: rows,
            dustThreshold: Self.bitcoinDust,
            ownUnconfirmedTxHashes: own
        )
    }

    // MARK: - Confirmation

    func testIncludesConfirmedOutputs() {
        XCTAssertEqual(filter([makeRow(blockId: 1)]).count, 1)
    }

    /// A confirmed output is spendable whether or not the wallet still has a
    /// pending record for the transaction that created it — the pending set is
    /// only ever consulted to rescue unconfirmed rows.
    func testIncludesConfirmedOutputsRegardlessOfThePendingSet() {
        XCTAssertEqual(filter([makeRow(blockId: 1, hash: "own")], own: ["own"]).count, 1)
        XCTAssertEqual(filter([makeRow(blockId: 1, hash: "foreign")], own: ["other"]).count, 1)
    }

    /// Blockchair marks mempool outputs with `block_id == -1`. One created by
    /// someone else can be replaced or evicted at will, so it never funds a
    /// transaction.
    func testExcludesForeignMempoolOutputs() {
        XCTAssertTrue(filter([makeRow(blockId: -1, hash: "stranger")], own: ["ours"]).isEmpty)
    }

    func testExcludesForeignUnconfirmedOutputsReportedAsBlockZero() {
        XCTAssertTrue(filter([makeRow(blockId: 0, hash: "stranger")], own: ["ours"]).isEmpty)
    }

    /// Absent evidence of a block is not evidence of one.
    func testExcludesForeignOutputsWithoutABlockId() {
        XCTAssertTrue(filter([makeRow(blockId: nil, hash: "stranger")], own: ["ours"]).isEmpty)
    }

    func testExcludesUnconfirmedOutputsWhenNothingIsPending() {
        XCTAssertTrue(filter([makeRow(blockId: -1, hash: "anything")]).isEmpty)
    }

    // MARK: - Our own unconfirmed change

    /// The output of a transaction this vault broadcast can only be replaced
    /// by re-spending inputs this vault exclusively controls, so admitting it
    /// carries none of the risk a stranger's zero-conf does. This is the case
    /// that keeps the wallet from reading 0 for a block after every send.
    func testAdmitsOurOwnUnconfirmedChange() {
        let utxos = filter([makeRow(blockId: -1, hash: "our-send")], own: ["our-send"])
        XCTAssertEqual(utxos.map(\.hash), ["our-send"])
    }

    func testAdmitsOurOwnUnconfirmedOutputReportedAsBlockZero() {
        XCTAssertEqual(filter([makeRow(blockId: 0, hash: "our-send")], own: ["our-send"]).count, 1)
    }

    func testAdmitsOurOwnUnconfirmedOutputWithoutABlockId() {
        XCTAssertEqual(filter([makeRow(blockId: nil, hash: "our-send")], own: ["our-send"]).count, 1)
    }

    /// Blockchair and WalletCore both emit lower-case hashes, but a broadcast
    /// proxy echoes back whatever it likes — the match must not hinge on it.
    func testMatchesOurOwnHashesCaseInsensitively() {
        XCTAssertEqual(filter([makeRow(blockId: -1, hash: "ABCD")], own: ["abcd"]).count, 1)
        XCTAssertEqual(filter([makeRow(blockId: -1, hash: "abcd")], own: ["ABCD"]).count, 1)
    }

    /// The admitted row keeps Blockchair's own spelling of the hash: it is what
    /// gets written into the input, not a normalised copy of it.
    func testPreservesTheProviderSpellingOfAnAdmittedHash() {
        XCTAssertEqual(filter([makeRow(blockId: -1, hash: "ABCD")], own: ["abcd"]).map(\.hash), ["ABCD"])
    }

    /// The pending set answers "is this ours", never "does this exist". A hash
    /// for a transaction that was dropped, evicted or never propagated matches
    /// no row, because the provider stopped reporting its outputs as unspent —
    /// which is why an optimistically-recorded broadcast cannot conjure an
    /// input out of a dead parent.
    func testAPendingHashNeverConjuresAnOutputTheProviderDoesNotReport() {
        XCTAssertTrue(filter([], own: ["dropped", "never-propagated"]).isEmpty)
        XCTAssertEqual(
            SpendableUtxos.balance(
                from: [],
                dustThreshold: Self.bitcoinDust,
                ownUnconfirmedTxHashes: ["dropped"]
            ),
            .zero
        )
    }

    /// Being pending vouches for a transaction's *own* outputs, nothing else.
    func testAPendingHashDoesNotAdmitUnrelatedUnconfirmedOutputs() {
        let rows = [
            makeRow(blockId: -1, hash: "ours", index: 1),
            makeRow(blockId: -1, hash: "theirs", index: 0)
        ]
        XCTAssertEqual(filter(rows, own: ["ours"]).map(\.hash), ["ours"])
    }

    /// Our own unconfirmed change still has to clear every other gate — being
    /// ours is a confirmation exemption, not a blanket one.
    func testOurOwnUnconfirmedChangeStillHonoursDustAndSpendability() {
        let rows = [
            makeRow(blockId: -1, hash: "ours", index: 0, value: Int(Self.bitcoinDust) - 1),
            makeRow(blockId: -1, hash: "ours", index: 1, value: 50_000, isSpendable: false)
        ]
        XCTAssertTrue(filter(rows, own: ["ours"]).isEmpty)
    }

    // MARK: - Spendability

    func testExcludesExplicitlyUnspendableOutputs() {
        XCTAssertTrue(filter([makeRow(isSpendable: false)]).isEmpty)
    }

    /// Blockchair omits `is_spendable` on Bitcoin entirely. Treating an absent
    /// field as "not spendable" would make every Bitcoin wallet unspendable.
    func testIncludesOutputsWithoutAnIsSpendableField() {
        XCTAssertEqual(filter([makeRow(isSpendable: nil)]).count, 1)
    }

    func testIncludesExplicitlySpendableOutputs() {
        XCTAssertEqual(filter([makeRow(isSpendable: true)]).count, 1)
    }

    // MARK: - Dust

    func testExcludesDustBelowTheChainThreshold() {
        XCTAssertTrue(filter([makeRow(value: Int(Self.bitcoinDust) - 1)]).isEmpty)
    }

    /// The threshold itself stays spendable — this pins the existing `>=`
    /// boundary so the filter doesn't quietly tighten it.
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

        let utxos = SpendableUtxos.select(from: rows, dustThreshold: dogeDust, ownUnconfirmedTxHashes: [])
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
        XCTAssertEqual(filter([makeRow(hash: "wide", index: Int(UInt32.max))]).map(\.index), [UInt32.max])
    }

    /// Every field on `BlockchairUtxo` is optional, so a shape-regressed row
    /// decodes cleanly and is then dropped in silence — the displayed balance
    /// comes out low with nothing anywhere failing. Counting them is what makes
    /// a provider or decode regression visible; a threshold on the gap between
    /// `address.balance` and the spendable sum could not be, because that gap
    /// is legitimately non-zero on any address holding a stranger's zero-conf
    /// or a sub-dust output.
    func testCountsRowsThatCannotIdentifyAnOutputAtAll() {
        let rows = [
            Blockchair.BlockchairUtxo(blockId: 900_000, transactionHash: nil, index: 0, value: 10_000),
            makeRow(hash: ""),
            makeRow(index: nil),
            makeRow(value: nil),
            makeRow(index: Int(UInt32.max) + 1)
        ]

        XCTAssertEqual(SpendableUtxos.unusableRowCount(in: rows), rows.count)
        XCTAssertTrue(filter(rows).isEmpty, "an unusable row is dropped as well as counted")
    }

    /// The count must not double as a policy alarm: an output that is dust,
    /// explicitly unspendable, or a stranger's zero-conf is excluded on
    /// purpose and is perfectly well-formed. Conflating the two would make the
    /// signal fire on every ordinary address and mean nothing.
    func testAPolicyExclusionIsNotCountedAsMalformed() {
        let rows = [
            makeRow(blockId: 900_000, hash: "dust", value: Int(Self.bitcoinDust) - 1),
            makeRow(blockId: 900_001, hash: "unspendable", isSpendable: false),
            makeRow(blockId: -1, hash: "stranger-zero-conf")
        ]

        XCTAssertEqual(SpendableUtxos.unusableRowCount(in: rows), 0)
        XCTAssertTrue(filter(rows).isEmpty, "all three are still excluded from the spendable set")
        XCTAssertEqual(SpendableUtxos.unusableRowCount(in: []), 0)
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

    /// The state the wallet is in for a block after every send: the input it
    /// spent has left the UTXO set and the change is sitting in the mempool.
    /// Withholding that change would leave a wallet that just sent 0.1 of 1.0
    /// showing nothing at all.
    func testChangeFromOurOwnSendRemainsSpendableWhileTheParentIsInTheMempool() {
        let rows = [makeRow(blockId: -1, hash: "our-send", index: 1, value: 90_000_000)]

        let utxos = filter(rows, own: ["our-send"])

        XCTAssertEqual(utxos.map(\.amount), [90_000_000])
    }

    // MARK: - Balance / spendable agreement

    /// The whole point of routing both numbers through one predicate: whatever
    /// the mix of rows, the balance is the sum of exactly the outputs that can
    /// fund a transaction. Any divergence here is a send that passes the
    /// balance check and fails at input selection.
    func testBalanceIsTheSumOfExactlyTheSpendableSet() {
        let rows = [
            makeRow(blockId: 900_001, hash: "confirmed", index: 0, value: 1_000_000),
            makeRow(blockId: -1, hash: "our-change", index: 1, value: 500_000),
            makeRow(blockId: -1, hash: "stranger-zero-conf", index: 0, value: 900_000),
            makeRow(blockId: 900_002, hash: "unspendable", index: 0, value: 800_000, isSpendable: false),
            makeRow(blockId: 900_003, hash: "dust", index: 0, value: Int(Self.bitcoinDust) - 1),
            makeRow(blockId: 900_004, hash: "malformed", index: nil, value: 700_000)
        ]
        let own: Set<String> = ["our-change"]

        let spendable = SpendableUtxos.select(
            from: rows,
            dustThreshold: Self.bitcoinDust,
            ownUnconfirmedTxHashes: own
        )
        let balance = SpendableUtxos.balance(
            from: rows,
            dustThreshold: Self.bitcoinDust,
            ownUnconfirmedTxHashes: own
        )

        XCTAssertEqual(spendable.map(\.hash), ["confirmed", "our-change"])
        XCTAssertEqual(balance, BigInt(1_500_000))
        XCTAssertEqual(balance, spendable.reduce(BigInt(0)) { $0 + BigInt($1.amount) })
    }

    /// The equality has to hold for the degenerate sets too, not just the
    /// interesting one.
    func testBalanceMatchesTheSpendableSetWhenNothingQualifies() {
        let rows = [
            makeRow(blockId: -1, hash: "stranger", index: 0, value: 900_000),
            makeRow(blockId: 900_000, hash: "dust", index: 0, value: 1)
        ]

        XCTAssertTrue(filter(rows).isEmpty)
        XCTAssertEqual(
            SpendableUtxos.balance(from: rows, dustThreshold: Self.bitcoinDust, ownUnconfirmedTxHashes: []),
            .zero
        )
    }

    func testBalanceOfAnEmptyResponseIsZero() {
        XCTAssertEqual(
            SpendableUtxos.balance(from: [], dustThreshold: Self.bitcoinDust, ownUnconfirmedTxHashes: []),
            .zero
        )
    }

    /// Summed as `BigInt` precisely so a holding that overflows the per-output
    /// `Int64` totals instead of trapping.
    func testBalanceSumsBeyondTheRangeOfASingleOutput() {
        let rows = (0..<4).map { index in
            makeRow(blockId: 900_000, hash: "big-\(index)", index: index, value: Int(Int64.max))
        }

        XCTAssertEqual(
            SpendableUtxos.balance(from: rows, dustThreshold: Self.bitcoinDust, ownUnconfirmedTxHashes: []),
            BigInt(Int64.max) * 4
        )
    }
}
