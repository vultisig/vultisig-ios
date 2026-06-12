//
//  KeygenVaultCommitTests.swift
//  VultisigAppTests
//
//  Pins the keygen-abort persistence fix: a secure keygen that is aborted at the
//  "Review Your Vaults" screen must NOT persist the vault, so its name stays
//  reusable. Only confirming ("Looks Good" -> `KeygenViewModel.commitVault`)
//  persists the vault and claims the name.
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class KeygenVaultCommitTests: XCTestCase {

    private var token: TestContextToken?

    override func setUp() async throws {
        try await super.setUp()
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() async throws {
        TestStore.restore(token)
        token = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeVault(name: String) -> Vault {
        Vault(
            name: name,
            signers: ["iPhone-Local", "iPad-Peer"],
            pubKeyECDSA: "02\(name.lowercased())ecdsa",
            pubKeyEdDSA: "ed\(name.lowercased())eddsa",
            keyshares: [],
            localPartyID: "iPhone-Local",
            hexChainCode: "00",
            resharePrefix: nil,
            libType: .DKLS
        )
    }

    private func persistedVaultCount() throws -> Int {
        try Storage.shared.modelContext.fetch(FetchDescriptor<Vault>()).count
    }

    // MARK: - Tests

    /// Aborting the review screen never calls `commitVault`, so an in-memory vault
    /// that was generated but not confirmed leaves nothing in the store and keeps
    /// its name available. This is the regression from #4493.
    func test_abortedKeygen_doesNotPersistVault_andNameStaysReusable() throws {
        let name = "Treasury"

        // Fresh store: the name is available.
        XCTAssertTrue(VaultNameValidator().validateNonThrowable(value: name))

        // Keygen produced a vault in memory, but the user aborted at review:
        // `commitVault` is never called.
        _ = makeVault(name: name)

        XCTAssertEqual(try persistedVaultCount(), 0, "Aborted keygen must persist no vault")
        XCTAssertTrue(
            VaultNameValidator().validateNonThrowable(value: name),
            "Name must remain reusable after an aborted keygen"
        )
    }

    /// Confirming ("Looks Good") persists the vault and the name becomes taken,
    /// case-insensitively — matching `VaultNameValidator`.
    func test_confirmedKeygen_persistsVault_andClaimsNameCaseInsensitively() throws {
        let name = "Treasury"
        let vault = makeVault(name: name)

        try KeygenViewModel.commitVault(vault, context: Storage.shared.modelContext)

        XCTAssertEqual(try persistedVaultCount(), 1, "Confirmed keygen must persist exactly one vault")

        // A new validator snapshots the now-persisted names.
        XCTAssertFalse(VaultNameValidator().validateNonThrowable(value: name))
        XCTAssertFalse(
            VaultNameValidator().validateNonThrowable(value: name.uppercased()),
            "Name uniqueness must be case-insensitive"
        )
    }

    /// Abort-then-retry with the same name succeeds: because the aborted attempt
    /// persisted nothing, committing the retried vault is accepted.
    func test_abortThenRetrySameName_succeeds() throws {
        let name = "Treasury"

        // First attempt aborted (never committed).
        _ = makeVault(name: name)
        XCTAssertTrue(VaultNameValidator().validateNonThrowable(value: name))

        // Retry with the same name, this time confirmed.
        let retry = makeVault(name: name)
        try KeygenViewModel.commitVault(retry, context: Storage.shared.modelContext)

        XCTAssertEqual(try persistedVaultCount(), 1)
        XCTAssertFalse(VaultNameValidator().validateNonThrowable(value: name))
    }
}
