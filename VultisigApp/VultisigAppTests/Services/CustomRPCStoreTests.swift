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
    }

    override func tearDown() async throws {
        store.reset(.ethereum)
        store.reset(.solana)
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
}
