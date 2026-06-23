//
//  CustomRPCStoreTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class CustomRPCStoreTests: XCTestCase {

    private var token: TestContextToken?
    private let store = CustomRPCStore.shared

    override func setUp() async throws {
        try await super.setUp()
        token = try TestStore.installInMemoryContainer()
        store.reloadFromStore()
        // Ensure a clean slate for the chains under test.
        store.reset(.ethereum)
        store.reset(.solana)
        store.reset(.polygon)
    }

    override func tearDown() async throws {
        store.reset(.ethereum)
        store.reset(.solana)
        store.reset(.polygon)
        TestStore.restore(token)
        token = nil
        try await super.tearDown()
    }

    func test_setOverride_reflectsInUrl() {
        XCTAssertNil(store.url(for: .ethereum))
        store.set("https://my-node.example/rpc", for: .ethereum)
        XCTAssertEqual(store.url(for: .ethereum), "https://my-node.example/rpc")
    }

    func test_setTrimsWhitespace() {
        store.set("  https://node.example/rpc  ", for: .ethereum)
        XCTAssertEqual(store.url(for: .ethereum), "https://node.example/rpc")
    }

    func test_resetClearsOverride() {
        store.set("https://node.example/rpc", for: .ethereum)
        store.reset(.ethereum)
        XCTAssertNil(store.url(for: .ethereum))
    }

    func test_overridesAreIndependentPerChain() {
        store.set("https://eth.example", for: .ethereum)
        XCTAssertNil(store.url(for: .solana))
        store.set("https://sol.example", for: .solana)
        XCTAssertEqual(store.url(for: .ethereum), "https://eth.example")
        XCTAssertEqual(store.url(for: .solana), "https://sol.example")
    }

    func test_reloadFromStore_hydratesMirrorFromPersistedRows() throws {
        // Persist directly via the context, then prove reload populates the mirror.
        let context = try XCTUnwrap(Storage.shared.modelContext)
        context.insert(CustomRPCOverride(chainRaw: Chain.ethereum.rawValue, url: "https://persisted.example"))
        try context.save()

        store.reloadFromStore()
        XCTAssertEqual(store.url(for: .ethereum), "https://persisted.example")
    }

    func test_setIsIdempotentUpsert() throws {
        store.set("https://first.example", for: .ethereum)
        store.set("https://second.example", for: .ethereum)
        XCTAssertEqual(store.url(for: .ethereum), "https://second.example")

        // Exactly one persisted row for the chain after two sets.
        let context = try XCTUnwrap(Storage.shared.modelContext)
        let chainRaw = Chain.ethereum.rawValue
        let descriptor = FetchDescriptor<CustomRPCOverride>(
            predicate: #Predicate { $0.chainRaw == chainRaw }
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        XCTAssertEqual(rows.count, 1)
    }

    // MARK: - Polygon aliasing (.polygon and .polygonV2 share one override slot)

    func test_polygonOverride_isVisibleUnderPolygonV2() {
        store.set("https://my-polygon.example/rpc", for: .polygon)
        XCTAssertEqual(store.url(for: .polygon), "https://my-polygon.example/rpc")
        XCTAssertEqual(store.url(for: .polygonV2), "https://my-polygon.example/rpc")
    }

    func test_polygonV2Override_isVisibleUnderPolygon() {
        store.set("https://my-polygon.example/rpc", for: .polygonV2)
        XCTAssertEqual(store.url(for: .polygon), "https://my-polygon.example/rpc")
        XCTAssertEqual(store.url(for: .polygonV2), "https://my-polygon.example/rpc")
    }

    func test_resetPolygon_clearsBothCases() {
        store.set("https://my-polygon.example/rpc", for: .polygonV2)
        store.reset(.polygon)
        XCTAssertNil(store.url(for: .polygon))
        XCTAssertNil(store.url(for: .polygonV2))
    }

    func test_polygonOverride_persistsUnderCanonicalKey() throws {
        store.set("https://my-polygon.example/rpc", for: .polygonV2)

        // The persisted row carries the canonical `polygon` key, never `polygonV2`.
        let context = try XCTUnwrap(Storage.shared.modelContext)
        let rows = try context.fetch(FetchDescriptor<CustomRPCOverride>())
        XCTAssertTrue(rows.contains { $0.chainRaw == Chain.polygon.rawValue })
        XCTAssertFalse(rows.contains { $0.chainRaw == Chain.polygonV2.rawValue })
    }

    // MARK: - Legacy polygonV2 migration

    func test_reloadFromStore_migratesLegacyPolygonV2RowOntoPolygon() throws {
        let context = try XCTUnwrap(Storage.shared.modelContext)
        context.insert(CustomRPCOverride(chainRaw: Chain.polygonV2.rawValue, url: "https://legacy-polygon.example"))
        try context.save()

        store.reloadFromStore()

        // Surfaces under both Polygon lookups...
        XCTAssertEqual(store.url(for: .polygon), "https://legacy-polygon.example")
        XCTAssertEqual(store.url(for: .polygonV2), "https://legacy-polygon.example")

        // ...and the orphaned polygonV2 row is gone, replaced by a polygon row.
        let rows = try context.fetch(FetchDescriptor<CustomRPCOverride>())
        XCTAssertFalse(rows.contains { $0.chainRaw == Chain.polygonV2.rawValue })
        XCTAssertTrue(rows.contains { $0.chainRaw == Chain.polygon.rawValue })
    }

    func test_reloadFromStore_legacyMigration_prefersExistingPolygonRow() throws {
        let context = try XCTUnwrap(Storage.shared.modelContext)
        context.insert(CustomRPCOverride(chainRaw: Chain.polygon.rawValue, url: "https://keep-polygon.example"))
        context.insert(CustomRPCOverride(chainRaw: Chain.polygonV2.rawValue, url: "https://drop-v2.example"))
        try context.save()

        store.reloadFromStore()

        XCTAssertEqual(store.url(for: .polygon), "https://keep-polygon.example")
        let rows = try context.fetch(FetchDescriptor<CustomRPCOverride>())
        XCTAssertFalse(rows.contains { $0.chainRaw == Chain.polygonV2.rawValue })
        XCTAssertEqual(rows.filter { $0.chainRaw == Chain.polygon.rawValue }.count, 1)
    }
}
