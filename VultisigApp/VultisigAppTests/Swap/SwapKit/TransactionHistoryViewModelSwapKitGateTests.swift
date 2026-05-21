//
//  TransactionHistoryViewModelSwapKitGateTests.swift
//  VultisigAppTests
//
//  Lock down the gate inside
//  `TransactionHistoryViewModel.pollInProgressTransactions` that keeps the
//  native `TransactionStatusPoller` away from SwapKit-routed rows under
//  normal conditions, and lets it take over as a fallback when
//  `swapKitTrackerOutage == true`.
//
//  Uses an in-process `SpyNativePoller` so the tests never spin up
//  per-chain RPC clients, never touch the wire, and never sleep.
//

import XCTest
@testable import VultisigApp

@MainActor
final class TransactionHistoryViewModelSwapKitGateTests: XCTestCase {

    func testSkipsSwapKitRoutedRowWhenTrackerOutageIsFalse() {
        let poller = SpyNativePoller()
        let vm = makeViewModel(poller: poller)
        vm.transactions = [Self.makeSwapKitInProgress(outage: false)]

        vm.pollInProgressTransactions()

        XCTAssertEqual(
            poller.pollCalls.count, 0,
            "Native poller must not be invoked for a SwapKit-routed row while /track is healthy"
        )
    }

    func testRunsNativePollerWhenSwapKitRowIsInTrackerOutage() {
        let poller = SpyNativePoller()
        let vm = makeViewModel(poller: poller)
        let outageRow = Self.makeSwapKitInProgress(outage: true)
        vm.transactions = [outageRow]

        vm.pollInProgressTransactions()

        XCTAssertEqual(
            poller.pollCalls.map(\.txHash),
            [outageRow.txHash],
            "Native poller must take over for the SwapKit row once /track outage is declared"
        )
    }

    func testRunsNativePollerForNonSwapKitRowRegardless() {
        let poller = SpyNativePoller()
        let vm = makeViewModel(poller: poller)
        let nativeRow = Self.makeNativeInProgress()
        vm.transactions = [nativeRow]

        vm.pollInProgressTransactions()

        XCTAssertEqual(
            poller.pollCalls.map(\.txHash),
            [nativeRow.txHash],
            "Non-SwapKit rows must continue to flow through the native poller"
        )
    }

    func testMixedRowsRouteCorrectly() {
        let poller = SpyNativePoller()
        let vm = makeViewModel(poller: poller)
        let nativeRow = Self.makeNativeInProgress()
        let healthySwapKitRow = Self.makeSwapKitInProgress(outage: false)
        let outageSwapKitRow = Self.makeSwapKitInProgress(outage: true)
        vm.transactions = [nativeRow, healthySwapKitRow, outageSwapKitRow]

        vm.pollInProgressTransactions()

        XCTAssertEqual(
            Set(poller.pollCalls.map(\.txHash)),
            Set([nativeRow.txHash, outageSwapKitRow.txHash]),
            "Only non-SwapKit + outage-SwapKit rows should reach native polling"
        )
        XCTAssertFalse(
            poller.pollCalls.contains(where: { $0.txHash == healthySwapKitRow.txHash }),
            "Healthy SwapKit-routed row must not appear in the native poller's call log"
        )
    }

    // MARK: - Fixtures

    private func makeViewModel(poller: SpyNativePoller) -> TransactionHistoryViewModel {
        TransactionHistoryViewModel(
            pubKeyECDSA: "vault-pub",
            vaultName: "Test Vault",
            chainFilter: nil,
            poller: poller
        )
    }

    private static func makeSwapKitInProgress(outage: Bool) -> TransactionHistoryData {
        TransactionHistoryData(
            id: UUID(),
            txHash: outage ? "0xsk-outage" : "0xsk-healthy",
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
            swapKitSwapId: "swap-1",
            swapKitRouteId: "route-1",
            swapKitBroadcastHash: outage ? "0xsk-outage" : "0xsk-healthy",
            swapKitSourceChainId: "1",
            swapKitProvider: "CHAINFLIP",
            swapKitLatestStatus: nil,
            swapKitLatestTrackingStatus: nil,
            swapKitLastPolledAt: nil,
            swapKitTrackingStartedAt: nil,
            swapKitTrackerOutage: outage
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

// MARK: - Spy

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
