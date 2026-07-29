//
//  UtxoSpendableBalanceTests.swift
//  VultisigAppTests
//
//  Covers the two halves of "displayed balance == spendable balance" on the
//  Blockchair-backed UTXO chains: `BalanceService.utxoBalanceSnapshot`, which
//  is what `fetchBalance` actually returns, and
//  `StoredPendingTransactionStorage.unconfirmedTransactionHashes`, which is
//  how the wallet recognises its own unconfirmed change. The two numbers used
//  to come from different fields of the same response and everything in the
//  gap was money the wallet showed and then refused to spend.
//

@testable import VultisigApp
import BigInt
import SwiftData
import WalletCore
import XCTest

final class UtxoSpendableBalanceTests: XCTestCase {

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

    private func makeEntry(
        reportedBalance: Int?,
        utxo: [Blockchair.BlockchairUtxo]?
    ) -> Blockchair {
        Blockchair(
            address: Blockchair.BlockchairAddress(
                scriptHex: nil,
                balance: reportedBalance,
                unspentOutputCount: utxo?.count
            ),
            utxo: utxo
        )
    }

    private func snapshot(
        _ entry: Blockchair,
        own: Set<String> = []
    ) throws -> BalanceService.BalanceSnapshot {
        try BalanceService.utxoBalanceSnapshot(
            from: entry,
            dustThreshold: Self.bitcoinDust,
            ownUnconfirmedTxHashes: own
        )
    }

    private func balance(
        _ entry: Blockchair,
        own: Set<String> = []
    ) throws -> String {
        try snapshot(entry, own: own).rawBalance
    }

    // MARK: - The equality this whole change exists for

    /// The displayed balance is the sum of exactly the outputs a transaction
    /// can be funded from — the stranger's zero-conf, the sub-dust output and
    /// the explicitly unspendable one are absent from both sides. Any
    /// divergence here is a send that clears `validateBalanceWithFee` and then
    /// dies at `notEnoughUTXOError`.
    func testBalanceEqualsTheSumOfTheSpendableSetForAMixedAddress() throws {
        let rows = [
            makeRow(blockId: 900_001, hash: "confirmed", index: 0, value: 1_000_000),
            makeRow(blockId: -1, hash: "our-change", index: 1, value: 500_000),
            makeRow(blockId: -1, hash: "stranger-zero-conf", index: 0, value: 900_000),
            makeRow(blockId: 900_002, hash: "unspendable", index: 0, value: 800_000, isSpendable: false),
            makeRow(blockId: 900_003, hash: "dust", index: 0, value: Int(Self.bitcoinDust) - 1)
        ]
        let own: Set<String> = ["our-change"]
        // Blockchair's own aggregate counts every one of them.
        let entry = makeEntry(reportedBalance: 3_200_545, utxo: rows)

        let spendable = SpendableUtxos.select(
            from: rows,
            dustThreshold: Self.bitcoinDust,
            ownUnconfirmedTxHashes: own
        )
        let reported = try balance(entry, own: own)

        XCTAssertEqual(spendable.map(\.hash), ["confirmed", "our-change"])
        XCTAssertEqual(reported, "1500000")
        XCTAssertEqual(
            reported,
            spendable.reduce(BigInt(0)) { $0 + BigInt($1.amount) }.description
        )
    }

    /// The state a wallet is in for a block after every send: the spent input
    /// is gone from the UTXO set and only the unconfirmed change is left.
    /// Without recognising it as ours, a wallet that sent 0.1 of a 1.0 BTC
    /// output would read 0.00 rather than 0.90.
    func testBalanceKeepsOurOwnChangeWhileTheParentIsUnconfirmed() throws {
        let entry = makeEntry(
            reportedBalance: 90_000_000,
            utxo: [makeRow(blockId: -1, hash: "our-send", index: 1, value: 90_000_000)]
        )

        XCTAssertEqual(try balance(entry, own: ["our-send"]), "90000000")
        XCTAssertEqual(try balance(entry), "0")
    }

    /// Money genuinely parked in outputs nothing can spend reads as zero, and
    /// that is the honest answer — it is the number the send flow will act on.
    func testBalanceIsZeroWhenEveryOutputIsPresentButFilteredOut() throws {
        let rows = [
            makeRow(blockId: -1, hash: "stranger", index: 0, value: 900_000),
            makeRow(blockId: 900_000, hash: "dust", index: 0, value: Int(Self.bitcoinDust) - 1)
        ]

        XCTAssertEqual(try balance(makeEntry(reportedBalance: 900_545, utxo: rows)), "0")
    }

    func testBalanceOfAnEmptyAddressIsZero() throws {
        XCTAssertEqual(try balance(makeEntry(reportedBalance: 0, utxo: [])), "0")
        XCTAssertEqual(try balance(makeEntry(reportedBalance: nil, utxo: [])), "0")
    }

    // MARK: - What is arriving, reported beside what is spendable

    /// An inbound payment still in the mempool raises the pending amount and
    /// leaves the spendable balance untouched. Folding it into the balance
    /// would restore the gap this whole change closes — a send would clear the
    /// balance check and then die at input selection, because a stranger's
    /// zero-conf is not something this wallet can build an input from.
    func testAnInboundZeroConfIsReportedAsPendingAndNotAsBalance() throws {
        let rows = [
            makeRow(blockId: 900_001, hash: "confirmed", index: 0, value: 1_000_000),
            makeRow(blockId: -1, hash: "inbound", index: 0, value: 250_000)
        ]

        let result = try snapshot(makeEntry(reportedBalance: 1_250_000, utxo: rows))

        XCTAssertEqual(result.rawBalance, "1000000")
        XCTAssertEqual(result.pendingRawBalance, "250000")
    }

    /// Our own unconfirmed change is spendable, so it is already in the
    /// balance — announcing it again as "arriving" would double-count the same
    /// money on one screen.
    func testOurOwnUnconfirmedChangeIsSpendableAndNeverPending() throws {
        let entry = makeEntry(
            reportedBalance: 90_000_000,
            utxo: [makeRow(blockId: -1, hash: "our-send", index: 1, value: 90_000_000)]
        )

        let result = try snapshot(entry, own: ["our-send"])

        XCTAssertEqual(result.rawBalance, "90000000")
        XCTAssertEqual(result.pendingRawBalance, "0")
    }

    /// The two numbers partition the outputs: nothing is counted twice and
    /// nothing that would be spendable on confirmation is dropped from both.
    func testSpendableAndPendingNeverOverlapAndNeverDoubleCount() throws {
        let rows = [
            makeRow(blockId: 900_001, hash: "confirmed", index: 0, value: 1_000_000),
            makeRow(blockId: -1, hash: "our-change", index: 1, value: 500_000),
            makeRow(blockId: -1, hash: "inbound", index: 0, value: 900_000)
        ]
        let own: Set<String> = ["our-change"]

        let result = try snapshot(makeEntry(reportedBalance: 2_400_000, utxo: rows), own: own)

        XCTAssertEqual(result.rawBalance, "1500000")
        XCTAssertEqual(result.pendingRawBalance, "900000")
        XCTAssertEqual(
            (BigInt(result.rawBalance) ?? 0) + (BigInt(result.pendingRawBalance) ?? 0),
            BigInt(2_400_000)
        )
    }

    /// Nothing arriving means no pending line at all — a permanent "+0 BTC
    /// pending" under the balance would be noise. This is also what makes the
    /// line *disappear*: the refresh after the payment confirms reports a
    /// pending amount of zero, which the apply path writes like any other, so
    /// the money moves from the pending line into the balance in one step.
    func testAnAddressWithNothingArrivingReportsNoPendingAmount() throws {
        let confirmed = [makeRow(blockId: 900_001, hash: "was-inbound", index: 0, value: 1_000_000)]

        let settled = try snapshot(makeEntry(reportedBalance: 1_000_000, utxo: confirmed))
        XCTAssertEqual(settled.rawBalance, "1000000")
        XCTAssertEqual(settled.pendingRawBalance, "0")

        XCTAssertEqual(try snapshot(makeEntry(reportedBalance: 0, utxo: [])).pendingRawBalance, "0")
    }

    // MARK: - Refusing a response that contradicts itself

    /// Deriving the balance from the rows makes their absence load-bearing.
    /// The pagination walk accepts an empty first page as provably complete,
    /// so a provider or proxy that dropped the `utxo` array would look exactly
    /// like an emptied wallet. Persisting that zero would block sends,
    /// send-max and swaps, so the fetch fails and the last known balance
    /// stands.
    func testRefusesAPositiveBalanceReportedWithNoUnspentOutputs() {
        for utxo in [nil, []] as [[Blockchair.BlockchairUtxo]?] {
            XCTAssertThrowsError(try balance(makeEntry(reportedBalance: 42_000, utxo: utxo))) { error in
                guard case BalanceService.Errors.utxoBalanceWithoutOutputs(let reported) = error else {
                    return XCTFail("expected utxoBalanceWithoutOutputs, got \(error)")
                }
                XCTAssertEqual(reported, 42_000)
            }
        }
    }

    /// A missing `address` block carries no claim to contradict, so it is not
    /// treated as one.
    func testAnAddressBlockWithoutABalanceIsNotTreatedAsAContradiction() throws {
        XCTAssertEqual(try balance(Blockchair(address: nil, utxo: nil)), "0")
        XCTAssertEqual(
            try balance(makeEntry(reportedBalance: nil, utxo: nil)),
            "0"
        )
    }

    // MARK: - Satoshi string shape

    /// `rawBalance` is a plain decimal string in the chain's smallest unit and
    /// is parsed as such downstream — the switch to `BigInt` must not add
    /// grouping, a sign, or scientific notation.
    func testProducesAPlainDecimalSatoshiString() throws {
        let entry = makeEntry(
            reportedBalance: 2_100_000_000_000_000,
            utxo: [makeRow(blockId: 900_000, hash: "whale", index: 0, value: 2_100_000_000_000_000)]
        )

        let reported = try balance(entry)

        XCTAssertEqual(reported, "2100000000000000")
        XCTAssertEqual(BigInt(reported), BigInt(2_100_000_000_000_000))
    }

    // MARK: - Recognising our own pending transactions

    @MainActor
    private func makeStorage() throws -> StoredPendingTransactionStorage {
        let schema = Schema([StoredPendingTransaction.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        containers.append(container)
        return StoredPendingTransactionStorage(modelContext: container.mainContext)
    }

    /// Held for the lifetime of the test: a `ModelContext` does not keep its
    /// container alive, and a deallocated store traps on the next fetch.
    private var containers: [ModelContainer] = []

    @MainActor
    func testUnconfirmedHashesAreScopedToTheChainAndTheVault() throws {
        let storage = try makeStorage()

        try storage.save(txHash: "btc-ours", chain: .bitcoin, status: .broadcasted(estimatedTime: ""), pubKeyECDSA: "vault-a")
        try storage.save(txHash: "btc-other-vault", chain: .bitcoin, status: .broadcasted(estimatedTime: ""), pubKeyECDSA: "vault-b")
        try storage.save(txHash: "ltc-ours", chain: .litecoin, status: .broadcasted(estimatedTime: ""), pubKeyECDSA: "vault-a")

        XCTAssertEqual(
            try storage.unconfirmedTransactionHashes(chain: .bitcoin, vaultPubKeyECDSA: "vault-a"),
            ["btc-ours"]
        )
        XCTAssertEqual(
            try storage.unconfirmedTransactionHashes(chain: .litecoin, vaultPubKeyECDSA: "vault-a"),
            ["ltc-ours"]
        )
        XCTAssertTrue(
            try storage.unconfirmedTransactionHashes(chain: .dogecoin, vaultPubKeyECDSA: "vault-a").isEmpty
        )
    }

    /// Confirmation is the only thing that ends the exemption, and it ends it
    /// harmlessly — a confirmed output carries a block and needs no vouching.
    @MainActor
    func testConfirmedAndUnattributedTransactionsAreExcluded() throws {
        let storage = try makeStorage()

        try storage.save(txHash: "broadcast", chain: .bitcoin, status: .broadcasted(estimatedTime: ""), pubKeyECDSA: "vault-a")
        try storage.save(txHash: "pending", chain: .bitcoin, status: .pending, pubKeyECDSA: "vault-a")
        try storage.save(txHash: "confirmed", chain: .bitcoin, status: .confirmed, pubKeyECDSA: "vault-a")
        try storage.save(txHash: "no-owner", chain: .bitcoin, status: .broadcasted(estimatedTime: ""), pubKeyECDSA: nil)

        XCTAssertEqual(
            try storage.unconfirmedTransactionHashes(chain: .bitcoin, vaultPubKeyECDSA: "vault-a"),
            ["broadcast", "pending"]
        )
    }

    /// The status poller gives up long before a mempool does. A low-fee
    /// transaction marked `timeout` — or `failed` on inconclusive evidence —
    /// can still be sitting in the mempool holding this wallet's only
    /// unconfirmed change, and dropping it there would send the balance back
    /// to zero for exactly the wallet this change exists to rescue.
    @MainActor
    func testAnInconclusiveTrackingStateStillVouchesForItsOutputs() throws {
        let storage = try makeStorage()

        try storage.save(txHash: "timed-out", chain: .bitcoin, status: .timeout, pubKeyECDSA: "vault-a")
        try storage.save(txHash: "failed", chain: .bitcoin, status: .failed(reason: "not found"), pubKeyECDSA: "vault-a")

        XCTAssertEqual(
            try storage.unconfirmedTransactionHashes(chain: .bitcoin, vaultPubKeyECDSA: "vault-a"),
            ["timed-out", "failed"]
        )
    }

    /// The broadcast write and the status poller race to create the same row,
    /// so whichever one carries the vault has to be able to attach it.
    @MainActor
    func testAnOwnerIsBackfilledOntoARowCreatedWithoutOne() throws {
        let storage = try makeStorage()

        try storage.save(txHash: "raced", chain: .bitcoin, status: .broadcasted(estimatedTime: ""), pubKeyECDSA: nil)
        XCTAssertTrue(try storage.unconfirmedTransactionHashes(chain: .bitcoin, vaultPubKeyECDSA: "vault-a").isEmpty)

        try storage.save(txHash: "raced", chain: .bitcoin, status: .broadcasted(estimatedTime: ""), pubKeyECDSA: "vault-a")

        XCTAssertEqual(
            try storage.unconfirmedTransactionHashes(chain: .bitcoin, vaultPubKeyECDSA: "vault-a"),
            ["raced"]
        )
    }

    /// A row already attributed keeps its owner — the backfill fills a hole,
    /// it does not reassign.
    @MainActor
    func testAnExistingOwnerIsNeverReassigned() throws {
        let storage = try makeStorage()

        try storage.save(txHash: "owned", chain: .bitcoin, status: .broadcasted(estimatedTime: ""), pubKeyECDSA: "vault-a")
        try storage.save(txHash: "owned", chain: .bitcoin, status: .pending, pubKeyECDSA: "vault-b")

        XCTAssertEqual(
            try storage.unconfirmedTransactionHashes(chain: .bitcoin, vaultPubKeyECDSA: "vault-a"),
            ["owned"]
        )
        XCTAssertTrue(
            try storage.unconfirmedTransactionHashes(chain: .bitcoin, vaultPubKeyECDSA: "vault-b").isEmpty
        )
    }

    /// A coin with no vault behind it — the key-import chain probe, say — asks
    /// for nothing and gets nothing, which lands it on a confirmed-only
    /// balance rather than on an unscoped match.
    func testAVaultlessLookupNeverTouchesTheStore() async throws {
        let hashes = try await SpendableUtxos.ownUnconfirmedTxHashes(chain: .bitcoin, vaultPubKeyECDSA: nil)
        let empty = try await SpendableUtxos.ownUnconfirmedTxHashes(chain: .bitcoin, vaultPubKeyECDSA: "")

        XCTAssertTrue(hashes.isEmpty)
        XCTAssertTrue(empty.isEmpty)
    }
}
