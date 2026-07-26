//
//  TransactionHistoryViewModelSwapKitGateTests.swift
//  VultisigAppTests
//
//  Lock down the gate inside
//  `TransactionHistoryViewModel.pollInProgressTransactions` that keeps the
//  native `TransactionStatusPoller` away from rows owned by a registered
//  `SwapTrackingService` under normal conditions, and lets it take over as
//  a fallback when `swapTracking.trackerOutage == true`.
//
//  Uses an in-process `SpyNativePoller` so the tests never spin up
//  per-chain RPC clients, never touch the wire, and never sleep. The
//  registry is swapped for a per-test instance with a registered fake
//  tracking service so the assertions are deterministic regardless of
//  registration order at app startup.
//

import XCTest
@testable import VultisigApp

@MainActor
final class TransactionHistoryViewModelSwapKitGateTests: XCTestCase {

    private let providerKind = "swapKit"

    func testSkipsTrackedRowWhenTrackerOutageIsFalse() {
        let poller = SpyNativePoller()
        let registry = makeRegistryWithFakeService()
        let vm = makeViewModel(poller: poller, registry: registry)
        vm.transactions = [Self.makeSwapKitInProgress(outage: false)]

        vm.pollInProgressTransactions()

        XCTAssertEqual(
            poller.pollCalls.count, 0,
            "Native poller must not be invoked for a tracked row while the tracker is healthy"
        )
    }

    func testRunsNativePollerWhenTrackedRowIsInTrackerOutage() {
        let poller = SpyNativePoller()
        let registry = makeRegistryWithFakeService()
        let vm = makeViewModel(poller: poller, registry: registry)
        let outageRow = Self.makeSwapKitInProgress(outage: true)
        vm.transactions = [outageRow]

        vm.pollInProgressTransactions()

        XCTAssertEqual(
            poller.pollCalls.map(\.txHash),
            [outageRow.txHash],
            "Native poller must take over for the tracked row once tracker outage is declared"
        )
    }

    func testRunsNativePollerForUntrackedRowRegardless() {
        let poller = SpyNativePoller()
        let registry = makeRegistryWithFakeService()
        let vm = makeViewModel(poller: poller, registry: registry)
        let nativeRow = Self.makeNativeInProgress()
        vm.transactions = [nativeRow]

        vm.pollInProgressTransactions()

        XCTAssertEqual(
            poller.pollCalls.map(\.txHash),
            [nativeRow.txHash],
            "Untracked rows must continue to flow through the native poller"
        )
    }

    func testMixedRowsRouteCorrectly() {
        let poller = SpyNativePoller()
        let registry = makeRegistryWithFakeService()
        let vm = makeViewModel(poller: poller, registry: registry)
        let nativeRow = Self.makeNativeInProgress()
        let healthyTrackedRow = Self.makeSwapKitInProgress(outage: false)
        let outageTrackedRow = Self.makeSwapKitInProgress(outage: true)
        vm.transactions = [nativeRow, healthyTrackedRow, outageTrackedRow]

        vm.pollInProgressTransactions()

        XCTAssertEqual(
            Set(poller.pollCalls.map(\.txHash)),
            Set([nativeRow.txHash, outageTrackedRow.txHash]),
            "Only untracked + outage-tracked rows should reach native polling"
        )
        XCTAssertFalse(
            poller.pollCalls.contains(where: { $0.txHash == healthyTrackedRow.txHash }),
            "Healthy tracked row must not appear in the native poller's call log"
        )
    }

    // MARK: - Fixtures

    private func makeRegistryWithFakeService() -> SwapTrackingRegistry {
        let registry = SwapTrackingRegistry()
        registry.register(FakeTrackingService())
        return registry
    }

    private func makeViewModel(
        poller: SpyNativePoller,
        registry: SwapTrackingRegistry
    ) -> TransactionHistoryViewModel {
        TransactionHistoryViewModel(
            pubKeyECDSA: "vault-pub",
            vaultName: "Test Vault",
            chainFilter: nil,
            poller: poller,
            registry: registry
        )
    }

    private static func makeSwapKitInProgress(outage: Bool) -> TransactionHistoryData {
        let txHash = outage ? "0xsk-outage" : "0xsk-healthy"
        return TransactionHistoryData(
            id: UUID(),
            txHash: txHash,
            approveTxHash: nil,
            pubKeyECDSA: "vault-pub",
            type: .swap,
            status: .inProgress,
            chainRawValue: "Ethereum",
            coinTicker: "ETH",
            coinLogo: "eth",
            coinChainLogo: nil,
            amountCrypto: "1.0",
            amountFiat: "2000",
            fromAddress: "0xfrom",
            toAddress: "0xto",
            toCoinTicker: "USDC",
            toCoinLogo: "usdc",
            toCoinChainLogo: nil,
            toAmountCrypto: "2000",
            toAmountFiat: "2000",
            swapProvider: "SwapKit (CHAINFLIP)",
            feeCrypto: "0.01",
            feeFiat: "20",
            network: "Ethereum",
            explorerLink: "https://etherscan.io/tx/0xsk",
            createdAt: Date(),
            completedAt: nil,
            estimatedTime: nil,
            errorMessage: nil,
            swapTracking: SwapTrackingMetadataData(
                providerKind: "swapKit",
                swapId: "swap-1",
                routeId: "route-1",
                broadcastHash: txHash,
                sourceChainId: "1",
                subProvider: "CHAINFLIP",
                trackerOutage: outage
            )
        )
    }

    private static func makeNativeInProgress() -> TransactionHistoryData {
        TransactionHistoryData(
            id: UUID(),
            txHash: "0xnative",
            approveTxHash: nil,
            pubKeyECDSA: "vault-pub",
            type: .send,
            status: .inProgress,
            chainRawValue: "Ethereum",
            coinTicker: "ETH",
            coinLogo: "eth",
            coinChainLogo: nil,
            amountCrypto: "1.0",
            amountFiat: "2000",
            fromAddress: "0xfrom",
            toAddress: "0xto",
            toCoinTicker: nil,
            toCoinLogo: nil,
            toCoinChainLogo: nil,
            toAmountCrypto: nil,
            toAmountFiat: nil,
            swapProvider: nil,
            feeCrypto: "0.01",
            feeFiat: "20",
            network: "Ethereum",
            explorerLink: "https://etherscan.io/tx/0xnative",
            createdAt: Date(),
            completedAt: nil,
            estimatedTime: nil,
            errorMessage: nil
        )
    }
}

// MARK: - Spy + Fake service

@MainActor
private final class SpyNativePoller: TransactionHistoryNativePoller {
    struct Call: Equatable {
        let txHash: String
    }

    private(set) var pollCalls: [Call] = []
    private(set) var stopCalls: [String] = []

    @discardableResult
    func poll(
        tx: TransactionHistoryData,
        onUpdate _: @escaping (TransactionHistoryStatus, String?) -> Void
    ) -> Bool {
        pollCalls.append(Call(txHash: tx.txHash))
        return true
    }

    func stopPolling(txHash: String) {
        stopCalls.append(txHash)
    }
}

@MainActor
private final class FakeTrackingService: SwapTrackingService {
    static var providerKind: String { "swapKit" }
    var uiStatusByTxHash: [String: SwapTrackingUiStatus] = [:]
    func start(tx _: TransactionHistoryData) {}
    func resumeInFlight() async {} // swiftlint:disable:this async_without_await
    func setActive(_: Bool) {}
    func stopAllTracking() {}
}
