import SwiftData
import XCTest
@testable import VultisigApp

@MainActor
final class TransactionHistoryDeepLinkTests: XCTestCase {
    func testResolvesExactRecordAndOwningVaultDespiteMatchingHash() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let context = token.container.mainContext
        let firstVault = TestStore.makeVault(pubKey: "first")
        let secondVault = TestStore.makeVault(pubKey: "second")
        let storage = TransactionHistoryStorage(modelContext: context)
        let first = ActivityTestFixture.row(hash: "shared-hash", vault: firstVault.pubKeyECDSA, status: .successful)
        let second = ActivityTestFixture.row(hash: "shared-hash", vault: secondVault.pubKeyECDSA, type: .swap, status: .successful)
        try storage.save(first)
        try storage.save(second)

        let route = try TransactionHistoryRoute.resolveDetail(recordID: second.id, context: context)
        XCTAssertEqual(route, .list(pubKeyECDSA: secondVault.pubKeyECDSA, vaultName: secondVault.name,
                                    chainFilter: nil, initialTransactionID: second.id))
    }

    func testMissingRecordOrDeletedVaultDoesNotResolve() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let context = token.container.mainContext
        let vault = TestStore.makeVault(pubKey: "deleted")
        let row = ActivityTestFixture.row(vault: vault.pubKeyECDSA, status: .successful)
        try TransactionHistoryStorage(modelContext: context).save(row)
        XCTAssertNil(try TransactionHistoryRoute.resolveDetail(recordID: UUID(), context: context))
        context.delete(vault)
        try context.save()
        XCTAssertNil(try TransactionHistoryRoute.resolveDetail(recordID: row.id, context: context))
    }

    func testHistorySelectsLinkedReceiptOnceAndKeepsItFresh() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = TestStore.makeVault(pubKey: "selection")
        let storage = TransactionHistoryStorage(modelContext: token.container.mainContext)
        let row = ActivityTestFixture.row(vault: vault.pubKeyECDSA, status: .successful)
        try storage.save(row)
        let viewModel = TransactionHistoryViewModel(pubKeyECDSA: vault.pubKeyECDSA, vaultName: vault.name,
                                                   chainFilter: nil, initialTransactionID: row.id, storage: storage)
        viewModel.load()
        XCTAssertEqual(viewModel.selectedDetail?.id, row.id)
        try storage.updateStatus(txHash: row.txHash, pubKeyECDSA: row.pubKeyECDSA, status: .error)
        viewModel.reloadTransactions()
        XCTAssertEqual(viewModel.selectedDetail?.status, .error)

        viewModel.selectedDetail = nil
        viewModel.load()
        XCTAssertNil(viewModel.selectedDetail, "Returning to history must not reopen a dismissed sheet")
    }

    func testDelayedEventRefreshesPersistedSwapOutage() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = TestStore.makeVault(pubKey: "outage")
        let storage = TransactionHistoryStorage(modelContext: token.container.mainContext)
        let row = ActivityTestFixture.row(vault: vault.pubKeyECDSA, type: .swap, status: .successful,
                                          tracking: .init(providerKind: "swapKit", latestTrackingStatus: "completed"))
        try storage.save(row)
        let viewModel = TransactionHistoryViewModel(pubKeyECDSA: vault.pubKeyECDSA, vaultName: vault.name,
                                                   chainFilter: nil, initialTransactionID: row.id, storage: storage)
        viewModel.load()
        try storage.updateSwapTrackingStatus(txHash: row.txHash, pubKeyECDSA: row.pubKeyECDSA,
                                             latestStatus: "unknown", latestTrackingStatus: "unknown",
                                             uiStatus: .unknownPendingExtended, polledAt: Date())
        let updated = try XCTUnwrap(storage.fetch(id: row.id))
        viewModel.reloadTransactions(after: .delayed(updated))
        XCTAssertEqual(viewModel.selectedDetail?.swapTracking?.trackerOutage, true)
        XCTAssertEqual(viewModel.selectedDetail?.swapTracking?.latestTrackingStatus, "unknown")
    }

    func testInitialSelectionCannotOpenAnotherVaultsReceipt() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let firstVault = TestStore.makeVault(pubKey: "visible")
        let secondVault = TestStore.makeVault(pubKey: "other")
        let row = ActivityTestFixture.row(vault: secondVault.pubKeyECDSA, status: .successful)
        let storage = TransactionHistoryStorage(modelContext: token.container.mainContext)
        try storage.save(row)
        let viewModel = TransactionHistoryViewModel(pubKeyECDSA: firstVault.pubKeyECDSA, vaultName: firstVault.name,
                                                   chainFilter: nil, initialTransactionID: row.id, storage: storage)
        viewModel.load()
        XCTAssertNil(viewModel.selectedDetail)
    }
}
