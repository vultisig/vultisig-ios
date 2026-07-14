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
        minOutputOverride: Decimal? = nil
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
            minOutputOverride: minOutputOverride
        )
    }
}
