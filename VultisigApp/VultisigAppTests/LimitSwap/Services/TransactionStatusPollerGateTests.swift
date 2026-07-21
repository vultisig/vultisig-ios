//
//  TransactionStatusPollerGateTests.swift
//  VultisigAppTests
//
//  The swap-tracker gate decides whether the native source-chain poller is
//  allowed to write a row's status. Getting it wrong in either direction is a
//  visible lie:
//
//  - too permissive → a source-chain confirmation marks a still-resting limit
//    order (or an in-flight cross-chain swap) Successful;
//  - too strict → an ordinary send never confirms at all.
//
//  The decision is a pure function so both directions are covered without the
//  poller's singletons or its network-backed task.
//

import XCTest
@testable import VultisigApp

@MainActor
final class TransactionStatusPollerGateTests: XCTestCase {

    private func makeRegistryWithLimitService() -> SwapTrackingRegistry {
        let registry = SwapTrackingRegistry()
        registry.register(THORChainLimitTrackingService(
            httpClient: NoopHTTPClient(),
            storage: NoopTrackingStorage(),
            orders: NoopLimitOrderObserver(),
            outcomes: NoopOutcomeResolver(),
            cancelIntents: NoopCancelIntentStore(),
            cancelVerifier: NoopCancelVerifier()
        ))
        return registry
    }

    // MARK: - Tracker owns the row

    func testTrackerIsAuthoritativeForATrackedLimitRow() {
        let tx = Self.makeTx(providerKind: "thorchainLimit")

        XCTAssertTrue(
            TransactionStatusPoller.isTrackerAuthoritative(for: tx, registry: makeRegistryWithLimitService())
        )
    }

    // MARK: - Tracker does not own the row

    /// The pre-fix limit row: no metadata, so nothing gates the native poller
    /// and it confirms the inbound deposit as Successful.
    func testTrackerIsNotAuthoritativeForARowWithoutTrackingMetadata() {
        let tx = Self.makeTx(providerKind: nil)

        XCTAssertFalse(
            TransactionStatusPoller.isTrackerAuthoritative(for: tx, registry: makeRegistryWithLimitService())
        )
    }

    /// An ordinary send must keep polling — a gate that fails "closed" here
    /// would stop every plain transaction from ever confirming.
    func testTrackerIsNotAuthoritativeWhenNoHistoryRowExists() {
        XCTAssertFalse(
            TransactionStatusPoller.isTrackerAuthoritative(for: nil, registry: makeRegistryWithLimitService())
        )
    }

    /// Metadata naming a provider nobody registered must not gate polling —
    /// otherwise the row would have no status source at all.
    func testTrackerIsNotAuthoritativeForAnUnregisteredProviderKind() {
        let tx = Self.makeTx(providerKind: "someFutureProvider")

        XCTAssertFalse(
            TransactionStatusPoller.isTrackerAuthoritative(for: tx, registry: makeRegistryWithLimitService())
        )
    }

    /// Outage hands authority back to native polling: a stale source-chain
    /// signal beats no signal at all.
    func testTrackerIsNotAuthoritativeDuringATrackerOutage() {
        let tx = Self.makeTx(providerKind: "thorchainLimit", trackerOutage: true)

        XCTAssertFalse(
            TransactionStatusPoller.isTrackerAuthoritative(for: tx, registry: makeRegistryWithLimitService())
        )
    }

    func testTrackerIsAuthoritativeWhenOutageIsExplicitlyFalse() {
        let tx = Self.makeTx(providerKind: "thorchainLimit", trackerOutage: false)

        XCTAssertTrue(
            TransactionStatusPoller.isTrackerAuthoritative(for: tx, registry: makeRegistryWithLimitService())
        )
    }

    /// An empty registry models the pre-registration state — nothing owns the
    /// row, so native polling proceeds.
    func testTrackerIsNotAuthoritativeWhenNoServiceIsRegistered() {
        let tx = Self.makeTx(providerKind: "thorchainLimit")

        XCTAssertFalse(
            TransactionStatusPoller.isTrackerAuthoritative(for: tx, registry: SwapTrackingRegistry())
        )
    }

    // MARK: - Fixtures

    private static func makeTx(
        providerKind: String?,
        trackerOutage: Bool? = nil
    ) -> TransactionHistoryData {
        TransactionHistoryData(
            id: UUID(),
            txHash: "limit-hash",
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
            explorerLink: "https://runescan.io/tx/limit-hash",
            createdAt: Date(),
            completedAt: nil,
            estimatedTime: nil,
            errorMessage: nil,
            swapTracking: providerKind.map { kind in
                SwapTrackingMetadataData(
                    providerKind: kind,
                    broadcastHash: "limit-hash",
                    sourceChainId: "THORChain",
                    trackerOutage: trackerOutage
                )
            }
        )
    }
}

// MARK: - Fakes

/// These cases only need the registry to RESOLVE a service for a row — the gate
/// keys off `providerKind` alone — so every collaborator is inert.
private final class NoopHTTPClient: HTTPClientProtocol {
    struct NoopError: Error {}

    func request(_: TargetType) async throws -> HTTPResponse<Data> { // swiftlint:disable:this async_without_await
        throw NoopError()
    }

    func requestEmpty(_: TargetType) async throws -> HTTPResponse<EmptyResponse> { // swiftlint:disable:this async_without_await
        throw NoopError()
    }
}

@MainActor
private final class NoopLimitOrderObserver: LimitOrderObserving {
    func recordObservation(
        inboundTxHash _: String,
        pubKeyECDSA _: String,
        status _: LimitOrderStatus,
        depositAmount _: String?,
        filledInAmount _: String?,
        filledOutAmount _: String?,
        observedTradeTarget _: String?,
        observedSourceAsset _: String?,
        observedTargetAsset _: String?,
        timeToExpiryBlocks _: Int?
    ) throws {}
}

@MainActor
private final class NoopCancelIntentStore: LimitOrderCancelIntentStoring {
    func pendingCancelBroadcast(inboundTxHash _: String, pubKeyECDSA _: String) -> String? { nil }
    func recordCancelBroadcast(inboundTxHash _: String, pubKeyECDSA _: String, txHash _: String) throws {}
    func clearCancelBroadcast(inboundTxHash _: String, pubKeyECDSA _: String, expecting _: String) throws {}
}

@MainActor
private final class NoopCancelVerifier: LimitOrderCancelVerifying {
    func verifyCancelTransaction(txHash _: String, chain _: Chain) async -> LimitOrderCancelTxOutcome { // swiftlint:disable:this async_without_await
        .unresolved
    }
}

@MainActor
private final class NoopOutcomeResolver: LimitOrderOutcomeResolving {
    func resolveOutcome(inboundTxHash _: String, sourceChain _: Chain) async -> LimitOrderOutcome { // swiftlint:disable:this async_without_await
        .unresolved
    }
}

private final class NoopTrackingStorage: SwapTrackingStorage {
    func updateSwapTrackingStatus(
        txHash _: String,
        pubKeyECDSA _: String,
        latestStatus _: String?,
        latestTrackingStatus _: String?,
        uiStatus _: SwapTrackingUiStatus,
        polledAt _: Date
    ) throws {}

    func touchSwapTrackingLastPolled(txHash _: String, pubKeyECDSA _: String, polledAt _: Date) throws {}

    func fetchInFlightSwapTracking(providerKind _: String) throws -> [TransactionHistoryData] { [] }
}
