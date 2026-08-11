//
//  TestStoreTests.swift
//  VultisigAppTests
//
//  Guards the fixture helper itself. `Vault` declares four
//  `@Attribute(.unique)` fields and SwiftData answers a duplicate with an
//  upsert rather than an error, so a helper that hard-codes one of them
//  collapses every fixture it builds into a single row — silently, with every
//  `for vault in fetch() { … }` assertion still passing over the survivor.
//

import SwiftData
import XCTest
@testable import VultisigApp

@MainActor
final class TestStoreTests: XCTestCase {
    private var token: TestContextToken!

    override func setUp() async throws {
        try await super.setUp()
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() async throws {
        TestStore.restore(token)
        token = nil
        try await super.tearDown()
    }

    /// The regression this file exists for: three fixtures must survive a save
    /// as three rows. While `pubKeyEdDSA` was hard-coded they collapsed into
    /// one, and a count assertion was the only thing that could see it.
    func testMakeVaultKeepsEveryFixtureAsItsOwnRow() throws {
        _ = TestStore.makeVault(pubKey: "vault-a")
        _ = TestStore.makeVault(pubKey: "vault-b")
        _ = TestStore.makeVault(pubKey: "vault-c")

        let context: ModelContext = Storage.shared.modelContext
        try context.save()

        let stored = try context.fetch(FetchDescriptor<Vault>())
        XCTAssertEqual(stored.count, 3, "fixtures collapsed on a unique attribute")
        XCTAssertEqual(Set(stored.map(\.name)).count, 3, "`name` is unique and must vary per fixture")
        XCTAssertEqual(Set(stored.map(\.pubKeyECDSA)).count, 3, "`pubKeyECDSA` is unique and must vary per fixture")
        XCTAssertEqual(Set(stored.map(\.pubKeyEdDSA)).count, 3, "`pubKeyEdDSA` is unique and must vary per fixture")
    }

    /// Proves the guard fires rather than being decorative. The same `pubKey`
    /// twice is exactly the shape that used to upsert in silence, and this also
    /// pins that the pre-insert lookup sees a still-unsaved fixture.
    func testMakeVaultFailsOnADuplicateFixture() {
        _ = TestStore.makeVault(pubKey: "duplicate")

        XCTExpectFailure("makeVault must flag a fixture that would upsert over an existing row")
        _ = TestStore.makeVault(pubKey: "duplicate")
    }

    /// A nil `publicKeyMLDSA44` is not a collision — a unique index treats NULLs
    /// as distinct. That is why the fixture leaves it nil rather than inventing
    /// a value, which would flip every `publicKeyMLDSA44 == nil` product branch
    /// for callers that only wanted a parent row.
    func testMakeVaultLeavesTheMLDSAKeyNilWithoutCollapsing() throws {
        _ = TestStore.makeVault(pubKey: "mldsa-a")
        _ = TestStore.makeVault(pubKey: "mldsa-b")

        let context: ModelContext = Storage.shared.modelContext
        try context.save()

        let stored = try context.fetch(FetchDescriptor<Vault>())
        XCTAssertEqual(stored.count, 2)
        XCTAssertTrue(stored.allSatisfy { $0.publicKeyMLDSA44 == nil })
    }
}
