//
//  LimitOrderStorageServiceTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class LimitOrderStorageServiceTests: XCTestCase {

    private var storeToken: TestContextToken!
    private var vault: Vault!
    private let service = LimitOrderStorageService()

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
        vault = TestStore.makeVault()
    }

    override func tearDown() async throws {
        vault = nil
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    // MARK: - persist

    func testPersistInsertsNewOrderForVault() throws {
        let record = makeRecord(inboundTxHash: "abc123")

        let order = try service.persist(record, for: vault)

        XCTAssertEqual(vault.limitOrders.count, 1)
        XCTAssertEqual(order.inboundTxHash, "abc123")
        XCTAssertEqual(order.sourceAsset, record.sourceAsset)
        XCTAssertEqual(order.targetPrice, record.targetPrice)
        XCTAssertEqual(order.expiryBlocks, record.expiryBlocks)
        XCTAssertEqual(order.statusRawValue, "pending")
    }

    /// The signed guaranteed-minimum output has to survive all the way into the
    /// table, not just into the in-memory record: the order card reads it back
    /// from here, and a value dropped at `persist` means showing a recomputed
    /// number instead of the one the user actually signed.
    func testPersistRoundTripsMinOutputOverride() throws {
        let record = makeRecord(inboundTxHash: "abc123", minOutputOverride: Decimal(string: "0.00512345")!)

        let order = try service.persist(record, for: vault)

        XCTAssertEqual(order.minOutputOverride, Decimal(string: "0.00512345")!)
    }

    func testPersistRoundTripsANilMinOutputOverride() throws {
        let order = try service.persist(makeRecord(inboundTxHash: "abc123"), for: vault)

        XCTAssertNil(order.minOutputOverride)
    }

    /// ⚠️ The full-contract spelling a cancel memo needs has to reach the table.
    /// Dropped here, an EVM-token leg is uncancellable until the queue reports
    /// the asset itself.
    func testPersistRoundTripsTheCancelAssetSpellings() throws {
        let record = makeRecord(
            inboundTxHash: "abc123",
            sourceAssetFull: "BTC.BTC",
            targetAssetFull: "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48"
        )

        let order = try service.persist(record, for: vault)

        XCTAssertEqual(order.sourceAssetFull, "BTC.BTC")
        XCTAssertEqual(order.targetAssetFull, "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48")
    }

    // MARK: - recordObservation

    /// The queue's own spelling of the assets is authoritative — it is what the
    /// order's index entry was built from — so it is recorded on every poll.
    func testRecordObservationStoresTheAssetsTheChainReports() throws {
        let order = try service.persist(makeRecord(inboundTxHash: "abc123"), for: vault)

        try service.recordObservation(
            of: order.id,
            status: .pending,
            observedSourceAsset: "THOR.RUNE",
            observedTargetAsset: "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
            in: vault
        )

        XCTAssertEqual(order.observedSourceAsset, "THOR.RUNE")
        XCTAssertEqual(order.observedTargetAsset, "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48")
    }

    /// `nil` is "not observed this poll" and must never clobber a good value —
    /// same rule as the fill split, and it matters at the same moment: a
    /// terminal write carries no assets at all.
    func testRecordObservationLeavesStoredAssetsAloneWhenNotObserved() throws {
        let order = try service.persist(makeRecord(inboundTxHash: "abc123"), for: vault)
        try service.recordObservation(
            of: order.id, status: .pending,
            observedSourceAsset: "THOR.RUNE", observedTargetAsset: "BTC.BTC",
            in: vault
        )

        try service.recordObservation(of: order.id, status: .refunded, in: vault)

        XCTAssertEqual(order.observedSourceAsset, "THOR.RUNE")
        XCTAssertEqual(order.observedTargetAsset, "BTC.BTC")
    }

    func testRecordObservationWritesStatusAndFillSplitTogether() throws {
        let order = try service.persist(makeRecord(inboundTxHash: "abc123"), for: vault)

        try service.recordObservation(
            of: order.id,
            status: .expired,
            depositAmount: "1000",
            filledInAmount: "400",
            filledOutAmount: "25",
            in: vault
        )

        XCTAssertEqual(order.status, .expired)
        XCTAssertEqual(order.depositAmount, "1000")
        XCTAssertEqual(order.filledInAmount, "400")
        XCTAssertEqual(order.filledOutAmount, "25")
    }

    /// A terminal order disappears from the queue, so the last observed split is
    /// all we will ever have. An observation that carries no amounts must not
    /// erase it — otherwise an order that expired 40% filled would forget it at
    /// the moment it went terminal.
    func testRecordObservationWithoutAmountsPreservesTheLastKnownSplit() throws {
        let order = try service.persist(makeRecord(inboundTxHash: "abc123"), for: vault)
        try service.recordObservation(
            of: order.id,
            status: .pending,
            depositAmount: "1000",
            filledInAmount: "400",
            filledOutAmount: "25",
            in: vault
        )

        try service.recordObservation(of: order.id, status: .expired, in: vault)

        XCTAssertEqual(order.status, .expired)
        XCTAssertEqual(order.depositAmount, "1000")
        XCTAssertEqual(order.filledInAmount, "400")
        XCTAssertEqual(order.filledOutAmount, "25")
    }

    func testRecordObservationThrowsForAnUnknownOrder() throws {
        XCTAssertThrowsError(try service.recordObservation(of: "nope", status: .filled, in: vault)) { error in
            guard case LimitOrderStorageError.notFound = error else {
                return XCTFail("Expected notFound, got \(error)")
            }
        }
    }

    // MARK: - fill progress

    func testFillFractionIsNilBeforeAnyObservation() throws {
        let order = try service.persist(makeRecord(inboundTxHash: "abc123"), for: vault)

        XCTAssertNil(order.fillFraction, "never observed is not the same as 0% filled")
        XCTAssertFalse(order.isPartiallyFilled)
    }

    func testFillFractionOfAPartiallyFilledOrder() throws {
        let order = try service.persist(makeRecord(inboundTxHash: "abc123"), for: vault)

        try service.recordObservation(
            of: order.id, status: .pending,
            depositAmount: "1000", filledInAmount: "400", filledOutAmount: "25",
            in: vault
        )

        XCTAssertEqual(order.fillFraction, Decimal(string: "0.4"))
        XCTAssertTrue(order.isPartiallyFilled)
    }

    func testAFullyFilledOrderIsNotPartiallyFilled() throws {
        let order = try service.persist(makeRecord(inboundTxHash: "abc123"), for: vault)

        try service.recordObservation(
            of: order.id, status: .filled,
            depositAmount: "1000", filledInAmount: "1000", filledOutAmount: "62",
            in: vault
        )

        XCTAssertEqual(order.fillFraction, 1)
        XCTAssertFalse(order.isPartiallyFilled)
    }

    func testAnUntouchedRestingOrderIsNotPartiallyFilled() throws {
        let order = try service.persist(makeRecord(inboundTxHash: "abc123"), for: vault)

        try service.recordObservation(
            of: order.id, status: .pending,
            depositAmount: "1000", filledInAmount: "0", filledOutAmount: "0",
            in: vault
        )

        XCTAssertEqual(order.fillFraction, 0)
        XCTAssertFalse(order.isPartiallyFilled)
    }

    /// A zero deposit must not divide — that's a crash, not a percentage.
    func testFillFractionIsNilForAZeroDeposit() throws {
        let order = try service.persist(makeRecord(inboundTxHash: "abc123"), for: vault)

        try service.recordObservation(
            of: order.id, status: .pending,
            depositAmount: "0", filledInAmount: "0", filledOutAmount: "0",
            in: vault
        )

        XCTAssertNil(order.fillFraction)
        XCTAssertFalse(order.isPartiallyFilled)
    }

    func testFillFractionIsNilForUnparseableAmounts() throws {
        let order = try service.persist(makeRecord(inboundTxHash: "abc123"), for: vault)

        try service.recordObservation(
            of: order.id, status: .pending,
            depositAmount: "not-a-number", filledInAmount: "400",
            in: vault
        )

        XCTAssertNil(order.fillFraction)
    }

    /// The protocol shouldn't report `in > deposit`; if it ever does, clamp
    /// rather than render "140% filled".
    func testFillFractionClampsAboveFull() throws {
        let order = try service.persist(makeRecord(inboundTxHash: "abc123"), for: vault)

        try service.recordObservation(
            of: order.id, status: .filled,
            depositAmount: "1000", filledInAmount: "1400",
            in: vault
        )

        XCTAssertEqual(order.fillFraction, 1)
        XCTAssertFalse(order.isPartiallyFilled)
    }

    /// 1e8 fixed-point amounts exceed Int32 and land near Int64 territory —
    /// they must not lose precision on the way to a fraction.
    func testFillFractionHandlesLarge1e8FixedPointAmounts() throws {
        let order = try service.persist(makeRecord(inboundTxHash: "abc123"), for: vault)

        try service.recordObservation(
            of: order.id, status: .pending,
            depositAmount: "37556623288", filledInAmount: "18778311644",
            in: vault
        )

        XCTAssertEqual(order.fillFraction, Decimal(string: "0.5"))
    }

    /// THORChain's accounting is `cosmos.Uint` (a big.Int), so these strings are
    /// arbitrary-precision. `Decimal` keeps only ~38 significant digits: parsing
    /// through it would round these two 40-digit values to the SAME number and
    /// report a partially-filled order as fully filled. Exact integer
    /// comparison must see the difference.
    func testPartialFillIsExactBeyondDecimalsPrecision() throws {
        let order = try service.persist(makeRecord(inboundTxHash: "abc123"), for: vault)
        // 40 digits, differing only in the final digit.
        let deposit = "1000000000000000000000000000000000000009"
        let filled = "1000000000000000000000000000000000000008"

        try service.recordObservation(
            of: order.id, status: .pending,
            depositAmount: deposit, filledInAmount: filled,
            in: vault
        )

        XCTAssertTrue(order.isPartiallyFilled, "filled < deposit must be exact, not rounded away")
    }

    /// The mirror case: genuinely equal huge amounts are fully filled.
    func testEqualHugeAmountsAreFullyFilled() throws {
        let order = try service.persist(makeRecord(inboundTxHash: "abc123"), for: vault)
        let amount = "1000000000000000000000000000000000000009"

        try service.recordObservation(
            of: order.id, status: .filled,
            depositAmount: amount, filledInAmount: amount,
            in: vault
        )

        XCTAssertFalse(order.isPartiallyFilled)
        XCTAssertEqual(order.fillFraction, 1)
    }

    /// A fill too small to register at display scale is still a partial fill —
    /// the remainder is still resting. The flag must not be decided by the
    /// rounded display fraction.
    func testATinyFillIsStillPartiallyFilled() throws {
        let order = try service.persist(makeRecord(inboundTxHash: "abc123"), for: vault)

        try service.recordObservation(
            of: order.id, status: .pending,
            depositAmount: "100000000000000", filledInAmount: "1",
            in: vault
        )

        XCTAssertTrue(order.isPartiallyFilled)
        XCTAssertEqual(order.fillFraction, 0, "rounds to 0% for display, but is still a partial fill")
    }

    func testFillFractionIsNilForANegativeFilledAmount() throws {
        let order = try service.persist(makeRecord(inboundTxHash: "abc123"), for: vault)

        try service.recordObservation(
            of: order.id, status: .pending,
            depositAmount: "1000", filledInAmount: "-5",
            in: vault
        )

        XCTAssertNil(order.fillFraction)
        XCTAssertFalse(order.isPartiallyFilled)
    }

    func testPersistGeneratesIdFromInboundHashAndPubKey() throws {
        let order = try service.persist(makeRecord(inboundTxHash: "abc123"), for: vault)
        XCTAssertEqual(order.id, "abc123_\(vault.pubKeyECDSA)")
    }

    func testPersistDuplicateInboundHashThrows() throws {
        _ = try service.persist(makeRecord(inboundTxHash: "abc123"), for: vault)

        XCTAssertThrowsError(try service.persist(makeRecord(inboundTxHash: "abc123"), for: vault)) { error in
            guard case let LimitOrderStorageError.duplicate(id) = error else {
                return XCTFail("Expected duplicate, got \(error)")
            }
            XCTAssertEqual(id, "abc123_\(vault.pubKeyECDSA)")
        }
    }

    func testPersistTwoOrdersWithDifferentHashesBothInsert() throws {
        _ = try service.persist(makeRecord(inboundTxHash: "abc"), for: vault)
        _ = try service.persist(makeRecord(inboundTxHash: "def"), for: vault)

        XCTAssertEqual(vault.limitOrders.count, 2)
    }

    // MARK: - empty inbound hash — collision guard (fund-safety)

    func testPersistEmptyInboundHashThrowsLoudly() throws {
        // The unique id is `inboundTxHash + pubKeyECDSA`. A pre-broadcast
        // record (empty hash) would produce id `"_pubkey"`, so two pending
        // orders would collide and silently drop one. `persist` must reject
        // an empty hash loudly instead.
        XCTAssertThrowsError(try service.persist(makeRecord(inboundTxHash: ""), for: vault)) { error in
            guard case LimitOrderStorageError.emptyInboundTxHash = error else {
                return XCTFail("Expected emptyInboundTxHash, got \(error)")
            }
        }
        XCTAssertTrue(vault.limitOrders.isEmpty)
    }

    func testTwoPendingEmptyHashOrdersCannotSilentlyCollide() throws {
        // Two distinct pending orders both with empty hashes: the second must
        // NOT silently overwrite / drop the first. Both attempts throw, and the
        // store stays empty rather than holding exactly one of the two.
        XCTAssertThrowsError(try service.persist(makeRecord(inboundTxHash: ""), for: vault))
        XCTAssertThrowsError(try service.persist(makeRecord(inboundTxHash: ""), for: vault))
        XCTAssertEqual(vault.limitOrders.count, 0)
    }

    // MARK: - fetchAll

    func testFetchAllReturnsOrdersSortedByCreatedAtDesc() throws {
        let earlier = Date().addingTimeInterval(-3600)
        let later = Date()

        _ = try service.persist(makeRecord(inboundTxHash: "old", createdAt: earlier), for: vault)
        _ = try service.persist(makeRecord(inboundTxHash: "new", createdAt: later), for: vault)

        let fetched = service.fetchAll(for: vault)

        XCTAssertEqual(fetched.map { $0.inboundTxHash }, ["new", "old"])
    }

    func testFetchAllForOtherVaultIsEmpty() throws {
        _ = try service.persist(makeRecord(inboundTxHash: "abc"), for: vault)

        let otherVault = TestStore.makeVault(pubKey: "other-vault")

        XCTAssertTrue(service.fetchAll(for: otherVault).isEmpty)
    }

    // MARK: - updateStatus

    func testUpdateStatusMutatesInPlace() throws {
        let order = try service.persist(makeRecord(inboundTxHash: "abc"), for: vault)

        try service.updateStatus(of: order.id, to: .filled, in: vault)

        XCTAssertEqual(order.statusRawValue, "filled")
        XCTAssertEqual(order.status, .filled)
    }

    func testUpdateStatusUnknownIdThrowsNotFound() {
        XCTAssertThrowsError(try service.updateStatus(of: "missing-id", to: .filled, in: vault)) { error in
            guard case let LimitOrderStorageError.notFound(id) = error else {
                return XCTFail("Expected notFound, got \(error)")
            }
            XCTAssertEqual(id, "missing-id")
        }
    }

    // MARK: - notification

    func testPersistPostsLimitOrdersDidChange() throws {
        let expectation = expectation(forNotification: .limitOrdersDidChange, object: nil, handler: nil)

        _ = try service.persist(makeRecord(inboundTxHash: "abc"), for: vault)

        wait(for: [expectation], timeout: 1.0)
    }

    func testUpdateStatusPostsLimitOrdersDidChange() throws {
        let order = try service.persist(makeRecord(inboundTxHash: "abc"), for: vault)
        let expectation = expectation(forNotification: .limitOrdersDidChange, object: nil, handler: nil)

        try service.updateStatus(of: order.id, to: .filled, in: vault)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Fixture builder

    private func makeRecord(
        inboundTxHash: String,
        createdAt: Date = Date(),
        minOutputOverride: Decimal? = nil,
        sourceAssetFull: String? = nil,
        targetAssetFull: String? = nil
    ) -> LimitOrderRecord {
        LimitOrderRecord(
            inboundTxHash: inboundTxHash,
            sourceAsset: "BTC.BTC",
            sourceAmount: "100000000",
            sourceDecimals: 8,
            targetAsset: "ETH.ETH",
            destAddress: "0xdeadbeef",
            targetPrice: 16,
            expiryBlocks: 14400,
            createdAt: createdAt,
            status: .pending,
            minOutputOverride: minOutputOverride,
            sourceAssetFull: sourceAssetFull,
            targetAssetFull: targetAssetFull
        )
    }
}
