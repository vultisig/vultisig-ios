//
//  TransactionHistoryResetServiceTests.swift
//  VultisigAppTests
//
//  The reset wipes BOTH stores and stops ALL polling, in that order (stop
//  before delete). These cover the orchestration, the real SwiftData deletions,
//  and the registry fan-out.
//

import SwiftData
import XCTest
@testable import VultisigApp

@MainActor
final class TransactionHistoryResetServiceTests: XCTestCase {

    // MARK: - Orchestration & ordering

    /// Every stop must run before either delete: an in-flight poll landing
    /// after a row is deleted could recreate it or write into a deleted object.
    func testResetStopsAllPollingBeforeDeletingEitherStore() {
        let recorder = Recorder()
        let service = TransactionHistoryResetService(
            stopStatusPolling: { recorder.log("stopStatus") },
            stopBackgroundPolling: { recorder.log("stopBackground") },
            stopSwapTracking: { recorder.log("stopTracking") },
            deleteTransactionHistory: { recorder.log("deleteTx") },
            deleteLimitOrders: { recorder.log("deleteOrders") },
            notifyChanged: { recorder.log("notify") }
        )

        service.resetAll()

        XCTAssertEqual(
            recorder.events,
            ["stopStatus", "stopBackground", "stopTracking", "deleteTx", "deleteOrders", "notify"]
        )
        let lastStop = recorder.events.lastIndex { $0.hasPrefix("stop") }!
        let firstDelete = recorder.events.firstIndex { $0.hasPrefix("delete") }!
        XCTAssertLessThan(lastStop, firstDelete, "All stops must precede any delete")
    }

    /// A failure wiping one store must not skip the other, and the refresh
    /// notification still fires so a live surface re-reads the emptied tables.
    func testResetWipesLimitOrdersEvenWhenTxHistoryDeleteThrows() {
        struct Boom: Error {}
        let recorder = Recorder()
        let service = TransactionHistoryResetService(
            stopStatusPolling: {},
            stopBackgroundPolling: {},
            stopSwapTracking: {},
            deleteTransactionHistory: { throw Boom() },
            deleteLimitOrders: { recorder.log("deleteOrders") },
            notifyChanged: { recorder.log("notify") }
        )

        service.resetAll()

        XCTAssertEqual(recorder.events, ["deleteOrders", "notify"])
    }

    // MARK: - Real deletions

    /// Clears the limit-order store across the vault, cancel intents included.
    func testDeleteAllLimitOrdersRemovesEveryOrderIncludingCancelIntents() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = TestStore.makeVault()
        let storage = LimitOrderStorageService()

        _ = try storage.persist(makeLimitRecord(inboundTxHash: "abc"), for: vault)
        let order2 = try storage.persist(makeLimitRecord(inboundTxHash: "def"), for: vault)
        // A recorded cancel proves the cancel-intent fields (stored on the order
        // itself) go with the order — no orphan intents survive.
        try storage.recordCancelBroadcast(of: order2.id, txHash: "cancel-hash", in: vault)
        XCTAssertEqual(vault.limitOrders.count, 2)

        try TransactionHistoryResetService.deleteAllLimitOrders()

        XCTAssertTrue(vault.limitOrders.isEmpty)
        let remaining = try Storage.shared.modelContext.fetch(FetchDescriptor<LimitOrder>())
        XCTAssertTrue(remaining.isEmpty)
    }

    /// `deleteAll()` clears every transaction-history row.
    func testTransactionHistoryStorageDeleteAllRemovesEveryRow() throws {
        let schema = Schema([TransactionHistoryItem.self, SwapTrackingMetadata.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let storage = TransactionHistoryStorage(modelContext: context)

        context.insert(makeHistoryItem(txHash: "0x1"))
        context.insert(makeHistoryItem(txHash: "0x2"))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TransactionHistoryItem>()), 2)

        try storage.deleteAll()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TransactionHistoryItem>()), 0)
    }

    // MARK: - Registry fan-out

    /// The registry's `stopAllTracking()` reaches every registered provider.
    func testRegistryStopAllTrackingFansOutToEveryRegisteredService() {
        let registry = SwapTrackingRegistry()
        let first = FakeTrackingServiceA()
        let second = FakeTrackingServiceB()
        registry.register(first)
        registry.register(second)

        registry.stopAllTracking()

        XCTAssertEqual(first.stopAllCount, 1)
        XCTAssertEqual(second.stopAllCount, 1)
    }

    // MARK: - Fixtures

    private func makeLimitRecord(inboundTxHash: String) -> LimitOrderRecord {
        LimitOrderRecord(
            inboundTxHash: inboundTxHash,
            sourceAsset: "THOR.RUNE",
            sourceAmount: "100",
            sourceDecimals: 8,
            targetAsset: "BTC.BTC",
            destAddress: "bc1qxyz",
            targetPrice: Decimal(string: "0.001")!,
            expiryBlocks: 14400
        )
    }

    private func makeHistoryItem(txHash: String) -> TransactionHistoryItem {
        TransactionHistoryItem(
            txHash: txHash,
            pubKeyECDSA: "vault-pub",
            typeRawValue: "send",
            statusRawValue: "successful",
            chainRawValue: "Ethereum",
            coinTicker: "ETH",
            coinLogo: "eth",
            amountCrypto: "1",
            amountFiat: "1",
            fromAddress: "a",
            toAddress: "b",
            feeCrypto: "0",
            feeFiat: "0",
            network: "Ethereum",
            explorerLink: "https://etherscan.io/tx/\(txHash)"
        )
    }
}

// MARK: - Fakes

/// Records call ordering across the injected seams. A class so the `@escaping`
/// closures can mutate it.
@MainActor
private final class Recorder {
    private(set) var events: [String] = []
    func log(_ event: String) { events.append(event) }
}

@MainActor
private final class FakeTrackingServiceA: SwapTrackingService {
    nonisolated static let providerKind = "fake-a"
    var uiStatusByTxHash: [String: SwapTrackingUiStatus] = [:]
    private(set) var stopAllCount = 0
    func start(tx _: TransactionHistoryData) {}
    func stop(txHash _: String) {}
    func resumeInFlight() async {} // swiftlint:disable:this async_without_await
    func setActive(_: Bool) {}
    func stopAllTracking() { stopAllCount += 1 }
}

@MainActor
private final class FakeTrackingServiceB: SwapTrackingService {
    nonisolated static let providerKind = "fake-b"
    var uiStatusByTxHash: [String: SwapTrackingUiStatus] = [:]
    private(set) var stopAllCount = 0
    func start(tx _: TransactionHistoryData) {}
    func stop(txHash _: String) {}
    func resumeInFlight() async {} // swiftlint:disable:this async_without_await
    func setActive(_: Bool) {}
    func stopAllTracking() { stopAllCount += 1 }
}
