//
//  TransactionStatusPollerSwapKitGateTests.swift
//  VultisigAppTests
//
//  Belt-and-suspenders coverage: the typed
//  `TransactionStatusPoller.poll(tx:onUpdate:)` entry point refuses to
//  schedule any per-chain RPC work for a SwapKit-routed row unless the
//  tracker has been declared in outage (`swapKitTrackerOutage == true`).
//  Mirrors the gate in `TransactionHistoryViewModel`; protects against a
//  future caller re-introducing the dual-polling regression that lets a
//  source-chain confirmation overwrite a still-in-flight cross-chain swap.
//

import XCTest
@testable import VultisigApp

@MainActor
final class TransactionStatusPollerSwapKitGateTests: XCTestCase {

    func testSwapKitRoutedRowWithoutOutageIsNoOp() {
        let poller = TransactionStatusPoller.shared
        let row = Self.makeSwapKitInProgress(outage: false)

        let scheduled = poller.poll(tx: row) { _, _ in
            XCTFail("onUpdate must not fire for a gated SwapKit row")
        }

        XCTAssertFalse(scheduled, "poll(tx:) must report no work scheduled for a healthy SwapKit row")
    }

    func testSwapKitRoutedRowWithOutageSchedulesWork() {
        // outage == true means /track has given up — native polling becomes
        // the fallback signal source. We don't want to actually run the
        // chain RPC in a unit test, so we immediately stop the task that
        // would have been started.
        let poller = TransactionStatusPoller.shared
        let row = Self.makeSwapKitInProgress(outage: true)

        let scheduled = poller.poll(tx: row) { _, _ in }
        defer { poller.stopPolling(txHash: row.txHash) }

        XCTAssertTrue(scheduled, "Outage SwapKit row must fall through the gate to native polling")
    }

    func testNonSwapKitRowAlwaysSchedules() {
        let poller = TransactionStatusPoller.shared
        let row = Self.makeNativeInProgress()

        let scheduled = poller.poll(tx: row) { _, _ in }
        defer { poller.stopPolling(txHash: row.txHash) }

        XCTAssertTrue(scheduled, "Non-SwapKit rows must always schedule native polling")
    }

    func testUnsupportedChainReturnsFalse() {
        // The typed entry point also short-circuits when the chain string
        // doesn't decode to a known `Chain` enum value — exercises the
        // `guard let chain = Chain(rawValue:)` branch.
        let poller = TransactionStatusPoller.shared
        let row = Self.makeNativeInProgress(chainRawValue: "NotARealChain")

        let scheduled = poller.poll(tx: row) { _, _ in }
        defer { poller.stopPolling(txHash: row.txHash) }

        XCTAssertFalse(scheduled)
    }

    // MARK: - Fixtures

    private static func makeSwapKitInProgress(outage: Bool) -> TransactionHistoryData {
        let hash = "0xpoller-sk-\(outage ? "outage" : "healthy")-\(UUID().uuidString)"
        return TransactionHistoryData(
            id: UUID(),
            txHash: hash,
            approveTxHash: nil,
            pubKeyECDSA: "vault-pub",
            type: .swap,
            status: .inProgress,
            chainRawValue: "ethereum",
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
            explorerLink: "https://etherscan.io/tx/\(hash)",
            createdAt: Date(),
            completedAt: nil,
            estimatedTime: nil,
            errorMessage: nil,
            swapKitSwapId: "swap-1",
            swapKitRouteId: "route-1",
            swapKitBroadcastHash: hash,
            swapKitSourceChainId: "1",
            swapKitProvider: "CHAINFLIP",
            swapKitTrackerOutage: outage
        )
    }

    private static func makeNativeInProgress(
        chainRawValue: String = "ethereum"
    ) -> TransactionHistoryData {
        let hash = "0xpoller-native-\(UUID().uuidString)"
        return TransactionHistoryData(
            id: UUID(),
            txHash: hash,
            approveTxHash: nil,
            pubKeyECDSA: "vault-pub",
            type: .send,
            status: .inProgress,
            chainRawValue: chainRawValue,
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
            network: chainRawValue,
            explorerLink: "https://etherscan.io/tx/\(hash)",
            createdAt: Date(),
            completedAt: nil,
            estimatedTime: nil,
            errorMessage: nil
        )
    }
}
