//
//  THORChainLimitTrackingStatusMapperTests.swift
//  VultisigAppTests
//
//  The limit mapper plus the `providerKind` dispatch that selects it. The
//  dispatch is the part worth pinning: before it, every row went through
//  SwapKit's table, where an unrecognised value falls through to `pending` — so
//  a resting order and an expired one rendered identically.
//

import XCTest
@testable import VultisigApp

final class THORChainLimitTrackingStatusMapperTests: XCTestCase {

    // MARK: - Mapping

    func testRestingIsMappedFromPendingAndIsNotTerminal() {
        XCTAssertEqual(THORChainLimitTrackingStatusMapper.map(.pending), .resting)
        XCTAssertFalse(SwapTrackingUiStatus.resting.isTerminal)
    }

    func testFilledMapsToCompletedAndIsTerminal() {
        XCTAssertEqual(THORChainLimitTrackingStatusMapper.map(.filled), .completed)
        XCTAssertTrue(SwapTrackingUiStatus.completed.isTerminal)
    }

    func testExpiredMapsToExpiredAndIsTerminal() {
        XCTAssertEqual(THORChainLimitTrackingStatusMapper.map(.expired), .expired)
        XCTAssertTrue(SwapTrackingUiStatus.expired.isTerminal)
    }

    /// What the tracker actually records when an order closes with the funds
    /// returned — the observed fact, not an inferred cause.
    func testRefundedMapsToRefundedAndIsTerminal() {
        XCTAssertEqual(THORChainLimitTrackingStatusMapper.map(.refunded), .refunded)
        XCTAssertTrue(SwapTrackingUiStatus.refunded.isTerminal)
    }

    func testCancelledMapsToCancelledAndIsTerminal() {
        XCTAssertEqual(THORChainLimitTrackingStatusMapper.map(.cancelled), .cancelled)
        XCTAssertTrue(SwapTrackingUiStatus.cancelled.isTerminal)
    }

    /// ⚠️ `.cancelling` is our own transaction landing, not the order closing.
    /// It has to stay NON-terminal or the tracker releases a live order and
    /// nothing is left to correct it.
    func testCancellingMapsToCancellingAndIsNotTerminal() {
        XCTAssertEqual(THORChainLimitTrackingStatusMapper.map(.cancelling), .cancelling)
        XCTAssertFalse(SwapTrackingUiStatus.cancelling.isTerminal)
        XCTAssertNotEqual(SwapTrackingUiStatus.cancelling, .cancelled)
    }

    /// The wire vocabulary is `LimitOrderStatus.rawValue` — one source, so the
    /// row can't contradict the order it mirrors.
    func testMapsEveryLimitOrderStatusRawValue() {
        XCTAssertEqual(THORChainLimitTrackingStatusMapper.map(trackingStatus: "pending"), .resting)
        XCTAssertEqual(THORChainLimitTrackingStatusMapper.map(trackingStatus: "cancelling"), .cancelling)
        XCTAssertEqual(THORChainLimitTrackingStatusMapper.map(trackingStatus: "filled"), .completed)
        XCTAssertEqual(THORChainLimitTrackingStatusMapper.map(trackingStatus: "expired"), .expired)
        XCTAssertEqual(THORChainLimitTrackingStatusMapper.map(trackingStatus: "cancelled"), .cancelled)
        XCTAssertEqual(THORChainLimitTrackingStatusMapper.map(trackingStatus: "refunded"), .refunded)
    }

    // MARK: - Fallbacks

    /// Nothing polled yet: resting, not terminal.
    func testNoRecordedStatusMapsToResting() {
        XCTAssertEqual(THORChainLimitTrackingStatusMapper.map(trackingStatus: nil), .resting)
        XCTAssertEqual(THORChainLimitTrackingStatusMapper.map(trackingStatus: ""), .resting)
    }

    /// An unrecognised status must never be guessed into a terminal state —
    /// nothing revisits a terminal order, so the mistake would be permanent.
    func testAnUnrecognisedStatusFallsBackToRestingNotTerminal() {
        let mapped = THORChainLimitTrackingStatusMapper.map(trackingStatus: "some_future_status")

        XCTAssertEqual(mapped, .resting)
        XCTAssertFalse(mapped.isTerminal)
    }

    /// SwapKit's own vocabulary is not this provider's. If one of its values
    /// ever reached this mapper it must not be honoured as terminal.
    func testSwapKitVocabularyIsNotHonouredHere() {
        XCTAssertEqual(THORChainLimitTrackingStatusMapper.map(trackingStatus: "completed"), .resting)
        XCTAssertEqual(THORChainLimitTrackingStatusMapper.map(trackingStatus: "outbound"), .resting)
    }

    // MARK: - providerKind dispatch

    func testALimitRowRoutesToTheLimitMapper() {
        let tx = Self.makeTx(providerKind: THORChainLimitTrackingService.providerKind, latestTrackingStatus: "expired")

        XCTAssertEqual(tx.swapTrackingUiStatus, .expired)
    }

    /// The regression the dispatch exists to prevent: routed through SwapKit's
    /// table, "expired" is unrecognised and falls through to `pending` — a
    /// settled order rendering as still in flight.
    func testALimitRowIsNotRoutedThroughTheSwapKitMapper() {
        let tx = Self.makeTx(providerKind: THORChainLimitTrackingService.providerKind, latestTrackingStatus: "expired")

        XCTAssertNotEqual(tx.swapTrackingUiStatus, SwapKitTrackingStatusMapper.map(trackingStatus: "expired"))
    }

    func testASwapKitRowStillRoutesToTheSwapKitMapper() {
        let tx = Self.makeTx(providerKind: SwapKitTrackingService.providerKind, latestTrackingStatus: "outbound")

        XCTAssertEqual(tx.swapTrackingUiStatus, .swapping)
    }

    /// A row with no tracking metadata keeps its previous behaviour.
    func testAnUntrackedRowFallsBackToTheSwapKitMapper() {
        let tx = Self.makeTx(providerKind: nil, latestTrackingStatus: nil)

        XCTAssertEqual(tx.swapTrackingUiStatus, .pending)
    }

    // MARK: - Fixtures

    private static func makeTx(
        providerKind: String?,
        latestTrackingStatus: String?
    ) -> TransactionHistoryData {
        TransactionHistoryData(
            id: UUID(),
            txHash: "hash",
            approveTxHash: nil,
            pubKeyECDSA: "vault-pub",
            type: .swap,
            status: .inProgress,
            chainRawValue: "THORChain",
            coinTicker: "RUNE",
            coinLogo: "rune",
            coinChainLogo: nil,
            amountCrypto: "600.12",
            amountFiat: "1000",
            fromAddress: "thor1from",
            toAddress: "bc1qto",
            toCoinTicker: "BTC",
            toCoinLogo: "btc",
            toCoinChainLogo: nil,
            toAmountCrypto: "0.0125",
            toAmountFiat: "1000",
            swapProvider: "THORChain",
            feeCrypto: "0.02",
            feeFiat: "0.04",
            network: "THORChain",
            explorerLink: "https://runescan.io/tx/hash",
            createdAt: Date(),
            completedAt: nil,
            estimatedTime: nil,
            errorMessage: nil,
            swapTracking: providerKind.map { kind in
                SwapTrackingMetadataData(
                    providerKind: kind,
                    broadcastHash: "hash",
                    sourceChainId: "THORChain",
                    latestTrackingStatus: latestTrackingStatus
                )
            }
        )
    }
}
