//
//  YieldPositionWriteGuardTests.swift
//  VultisigAppTests
//
//  `YieldPositionStorageService.upsert(...)` must leave the store completely
//  alone when the refreshed snapshot already matches what is persisted — both
//  halves of it: the position's own balances, and its redemption rows.
//
//  Asserting on the resulting VALUES cannot show that. A blind re-assignment of
//  an identical value leaves the values identical, and a delete-then-recreate of
//  identical rows leaves the rows looking identical too, so a test written that
//  way passes against the unguarded implementation as happily as against this
//  one. What separates them is the mutation: SwiftData's `@Model` setter routes
//  through the Observation registrar and notifies WITHOUT comparing new to old,
//  and a deleted-and-reinserted row is a genuine store change no equality guard
//  can suppress. Both invalidate every SwiftUI reader — and, once the caller
//  saves, every `@Query` in the app, whatever type it queries — on every refresh
//  however little actually moved.
//
//  So these tests observe with `withObservationTracking` and assert on whether a
//  change was published, and — for the redemption diff — on OBJECT IDENTITY:
//  a row that survived a refresh untouched is the same instance afterwards, and
//  a recreated one is not. That is the assertion the delete-recreate fails.
//
//  The per-field sweeps are the other half. The failure they prevent is a field
//  that is written but not compared: the guard returns early, the write never
//  runs, and a real update is silently dropped. Every field either guard assigns
//  gets its own case.
//

@testable import VultisigApp
import Observation
import SwiftData
import XCTest

/// Reference box so the `@Sendable` `onChange` closure can report back without
/// capturing a mutable local. Every access is main-actor and synchronous —
/// `onChange` fires from inside the mutating call, on the same thread.
private final class ChangeRecorder: @unchecked Sendable {
    private(set) var didChange = false
    func record() { didChange = true }
}

private func redemption(
    id: String = "req-1",
    amount: Decimal = 95,
    requestedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
    claimableAt: Date? = Date(timeIntervalSince1970: 1_700_600_000),
    status: YieldRedemption.Status = .pending
) -> YieldRedemption {
    YieldRedemption(
        id: id,
        amount: amount,
        requestedAt: requestedAt,
        claimableAt: claimableAt,
        status: status
    )
}

@MainActor
final class YieldPositionWriteGuardTests: XCTestCase {

    private var token: TestContextToken!
    private let service = YieldPositionStorageService()
    private var vault: Vault!

    override func setUpWithError() throws {
        token = try TestStore.installInMemoryContainer()
        vault = TestStore.makeVault(pubKey: "yield-guard")
    }

    override func tearDown() {
        vault = nil
        TestStore.restore(token)
        token = nil
    }

    // MARK: - Helpers

    /// Runs `mutate` while observing everything `read` touches, and reports
    /// whether the Observation registrar published a change.
    private func changePublished(reading read: () -> Void, during mutate: () throws -> Void) rethrows -> Bool {
        let recorder = ChangeRecorder()
        withObservationTracking { read() } onChange: { recorder.record() }
        try mutate()
        return recorder.didChange
    }

    /// Reads every property the balance guard can write. All of them have to be
    /// observed: a property written but not read here could be mutated without
    /// the probe noticing, and the test would pass vacuously.
    private func readPositionFields(_ position: YieldPosition) {
        _ = position.depositedBalance
        _ = position.nativeGasBalance
        _ = position.lastUpdated
        _ = position.redemptions
    }

    /// Reads every property the redemption guard can write. `id` is the match
    /// key and is never written, so it is deliberately absent.
    private func readRecordFields(_ record: YieldRedemptionRecord) {
        _ = record.amount
        _ = record.requestedAt
        _ = record.claimableAt
        _ = record.statusRawValue
    }

    @discardableResult
    private func upsert(
        deposited: Decimal = 100,
        gas: Decimal = 0.2,
        redemptions: [YieldRedemption] = []
    ) throws -> YieldPosition {
        try service.upsert(
            providerID: .circle,
            depositedBalance: deposited,
            nativeGasBalance: gas,
            redemptions: redemptions,
            for: vault
        )
        return try XCTUnwrap(service.position(for: vault, providerID: .circle))
    }

    /// Row identity as the STORE sees it. Deliberately not `ObjectIdentifier`:
    /// SwiftData re-materializes fresh Swift instances for the same persisted row
    /// after a save, so instance identity changes for reasons that have nothing
    /// to do with the row being deleted and recreated. `persistentModelID`
    /// survives that and does not survive a delete plus an insert.
    private func identities(of position: YieldPosition) -> Set<PersistentIdentifier> {
        Set(position.redemptions.map(\.persistentModelID))
    }

    private func record(_ position: YieldPosition, id: String) throws -> YieldRedemptionRecord {
        try XCTUnwrap(position.redemptions.first { $0.id == id })
    }

    /// Every redemption row in the store, not just the ones still hanging off the
    /// position — a row dropped from the relationship but left behind in the
    /// store is an orphan, and the delete has to be asserted where it happens.
    /// `isDeleted` cannot be used for this: it goes back to `false` once the
    /// delete is saved.
    private func storedRedemptionIDs() throws -> Set<String> {
        let rows = try Storage.shared.modelContext.fetch(FetchDescriptor<YieldRedemptionRecord>())
        return Set(rows.map(\.id))
    }

    // MARK: - Balances: the no-op case

    func testUpsertWithIdenticalSnapshotPublishesNoChange() throws {
        let position = try upsert()

        let published = try changePublished(reading: { readPositionFields(position) }, during: {
            try upsert()
        })

        XCTAssertFalse(
            published,
            "An identical snapshot must not mutate the position. SwiftData notifies without comparing, "
                + "so any blind re-assignment re-invalidates every SwiftUI reader."
        )
    }

    /// The stamp has to sit INSIDE the guard. Left outside it re-notifies on its
    /// own on every call and the guard buys nothing, so this is asserted
    /// separately rather than folded into the probe above.
    func testUpsertWithIdenticalSnapshotLeavesLastUpdatedUntouched() async throws {
        let position = try upsert()
        let stampBefore = position.lastUpdated

        // Enough of a gap that a re-stamp would be unambiguous rather than a
        // sub-microsecond tie.
        try await Task.sleep(for: .milliseconds(20))
        try upsert()

        XCTAssertEqual(position.lastUpdated, stampBefore, "A no-op refresh must not refresh lastUpdated.")
    }

    // MARK: - Balances: the real-update case

    func testUpsertPublishesChangeForEveryBalanceFieldDifference() async throws {
        let cases: [(field: String, deposited: Decimal, gas: Decimal)] = [
            ("depositedBalance", 101, 0.2),
            ("nativeGasBalance", 100, 0.9)
        ]

        for testCase in cases {
            let position = try upsert(deposited: 100, gas: 0.2)
            let stampBefore = position.lastUpdated
            try await Task.sleep(for: .milliseconds(20))

            let published = try changePublished(reading: { readPositionFields(position) }, during: {
                try upsert(deposited: testCase.deposited, gas: testCase.gas)
            })

            XCTAssertTrue(
                published,
                "\(testCase.field) differs from the stored value — upsert must write it"
            )
            XCTAssertEqual(position.depositedBalance, testCase.deposited)
            XCTAssertEqual(position.nativeGasBalance, testCase.gas)
            XCTAssertGreaterThan(position.lastUpdated, stampBefore, "A real update must refresh lastUpdated.")
        }
    }

    // MARK: - Redemptions: the unchanged set

    /// The decisive test for the diff. Under a delete-and-recreate every row is
    /// a new instance on every refresh, so the identity set cannot survive.
    func testUnchangedRedemptionSnapshotKeepsTheSameRowInstances() throws {
        let rows = [redemption(id: "req-1"), redemption(id: "req-2", amount: 5, status: .claimable)]
        let position = try upsert(redemptions: rows)
        let before = identities(of: position)
        XCTAssertEqual(before.count, 2)

        try upsert(redemptions: rows)

        XCTAssertEqual(
            identities(of: position),
            before,
            "An unchanged snapshot must reuse the stored rows, not delete and recreate them."
        )
        XCTAssertEqual(position.redemptions.count, 2)
        XCTAssertEqual(try storedRedemptionIDs(), ["req-1", "req-2"])
    }

    func testUnchangedRedemptionSnapshotPublishesNoChange() throws {
        let rows = [redemption(id: "req-1"), redemption(id: "req-2", amount: 5, status: .claimable)]
        let position = try upsert(redemptions: rows)
        let stored = position.redemptions

        let published = try changePublished(reading: {
            readPositionFields(position)
            stored.forEach { readRecordFields($0) }
        }, during: {
            try upsert(redemptions: rows)
        })

        XCTAssertFalse(published, "An unchanged redemption snapshot must not mutate anything.")
    }

    // MARK: - Redemptions: one row changed

    func testChangedRedemptionUpdatesOnlyThatRow() throws {
        let untouched = redemption(id: "req-1")
        let position = try upsert(redemptions: [untouched, redemption(id: "req-2", amount: 5, status: .pending)])
        let before = identities(of: position)
        let stableRow = try record(position, id: "req-1")

        let stablePublished = try changePublished(reading: { readRecordFields(stableRow) }, during: {
            try upsert(redemptions: [untouched, redemption(id: "req-2", amount: 5, status: .claimable)])
        })

        XCTAssertFalse(stablePublished, "The row that did not change must not be written.")
        XCTAssertEqual(identities(of: position), before, "Neither row may be recreated.")
        XCTAssertEqual(try record(position, id: "req-2").status, .claimable)
        XCTAssertEqual(try record(position, id: "req-1").status, .pending)
    }

    /// One case per field the redemption guard assigns. Catches a field that is
    /// assigned but missing from the comparison, which would make the early
    /// return swallow a real update.
    func testRedemptionPublishesChangeForEverySingleFieldDifference() throws {
        let baseline = redemption()
        let cases: [(field: String, changed: YieldRedemption, verify: (YieldRedemptionRecord) -> Void)] = [
            ("amount", redemption(amount: 96), { XCTAssertEqual($0.amount, 96) }),
            ("requestedAt", redemption(requestedAt: Date(timeIntervalSince1970: 1_700_000_500)),
             { XCTAssertEqual($0.requestedAt, Date(timeIntervalSince1970: 1_700_000_500)) }),
            ("claimableAt", redemption(claimableAt: Date(timeIntervalSince1970: 1_700_700_000)),
             { XCTAssertEqual($0.claimableAt, Date(timeIntervalSince1970: 1_700_700_000)) }),
            ("claimableAt→nil", redemption(claimableAt: nil), { XCTAssertNil($0.claimableAt) }),
            ("status", redemption(status: .settled), { XCTAssertEqual($0.status, .settled) })
        ]

        for testCase in cases {
            let position = try upsert(redemptions: [baseline])
            let stored = try record(position, id: baseline.id)

            let published = try changePublished(reading: { readRecordFields(stored) }, during: {
                try upsert(redemptions: [testCase.changed])
            })

            XCTAssertTrue(published, "\(testCase.field) differs from the stored value — the sync must write it")
            XCTAssertEqual(
                identities(of: position),
                [stored.persistentModelID],
                "\(testCase.field): the row must be updated in place, not replaced"
            )
            testCase.verify(stored)

            // Reset for the next case: the position is keyed on the vault, so
            // every case shares it.
            try upsert(redemptions: [])
        }
    }

    // MARK: - Redemptions: membership changes

    func testUpsertInsertsAddedRowAndDeletesRemovedRowOnly() throws {
        let kept = redemption(id: "req-1")
        let position = try upsert(redemptions: [kept, redemption(id: "req-2", amount: 5)])
        let keptRowID = try record(position, id: "req-1").persistentModelID

        try upsert(redemptions: [kept, redemption(id: "req-3", amount: 7)])

        XCTAssertEqual(Set(position.redemptions.map(\.id)), ["req-1", "req-3"])
        XCTAssertTrue(
            identities(of: position).contains(keptRowID),
            "The row present in both snapshots must survive as the same stored row."
        )
        XCTAssertEqual(
            try storedRedemptionIDs(),
            ["req-1", "req-3"],
            "The row absent from the snapshot must be deleted from the store, not just detached."
        )
        XCTAssertEqual(try record(position, id: "req-3").amount, 7)
    }

    func testUpsertPopulatesRedemptionsFromEmpty() throws {
        let position = try upsert(redemptions: [])
        XCTAssertTrue(position.redemptions.isEmpty)

        try upsert(redemptions: [redemption(id: "req-1"), redemption(id: "req-2", amount: 5)])

        XCTAssertEqual(Set(position.redemptions.map(\.id)), ["req-1", "req-2"])
        XCTAssertEqual(try record(position, id: "req-1").amount, 95)
    }

    func testUpsertClearsEveryRedemptionWhenSnapshotIsEmpty() throws {
        let position = try upsert(redemptions: [redemption(id: "req-1"), redemption(id: "req-2", amount: 5)])
        XCTAssertEqual(try storedRedemptionIDs().count, 2)

        try upsert(redemptions: [])

        XCTAssertTrue(position.redemptions.isEmpty)
        XCTAssertTrue(
            try storedRedemptionIDs().isEmpty,
            "Rows dropped from the snapshot must be deleted, not orphaned in the store."
        )
    }

    /// The empty-to-empty transition is the one production actually runs today —
    /// Circle is instant and always supplies no redemptions — so it is the case
    /// that must not churn.
    func testEmptySnapshotOverEmptyRowsPublishesNoChange() throws {
        let position = try upsert(redemptions: [])

        let published = try changePublished(reading: { readPositionFields(position) }, during: {
            try upsert(redemptions: [])
        })

        XCTAssertFalse(published, "An empty snapshot over no rows must not touch the relationship.")
    }

    /// Two incoming rows sharing an id would collide on `@Attribute(.unique)`;
    /// the sync keeps the first and drops the rest rather than letting SwiftData
    /// silently upsert them into one.
    func testDuplicateIncomingRedemptionIdsCollapseToOneRow() throws {
        let position = try upsert(redemptions: [
            redemption(id: "req-1", amount: 95),
            redemption(id: "req-1", amount: 42)
        ])

        XCTAssertEqual(position.redemptions.count, 1)
        XCTAssertEqual(try record(position, id: "req-1").amount, 95)
    }
}
