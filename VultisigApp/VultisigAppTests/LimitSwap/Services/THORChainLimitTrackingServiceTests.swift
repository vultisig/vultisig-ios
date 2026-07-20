//
//  THORChainLimitTrackingServiceTests.swift
//  VultisigAppTests
//
//  Covers the Phase 1 contract: registering this provider is what stops a
//  resting limit order from being reported as Successful by the native
//  source-chain poller. The poll loop itself lands in Phase 2.
//

import XCTest
@testable import VultisigApp

@MainActor
final class THORChainLimitTrackingServiceTests: XCTestCase {

    // MARK: - Provider identity

    func testProviderKindIsThorchainLimit() {
        XCTAssertEqual(THORChainLimitTrackingService.providerKind, "thorchainLimit")
    }

    /// The two providers must never collide — the registry is keyed by this
    /// string, so an accidental match would let one provider silently take
    /// ownership of the other's rows.
    func testProviderKindIsDistinctFromSwapKit() {
        XCTAssertNotEqual(
            THORChainLimitTrackingService.providerKind,
            SwapKitTrackingService.providerKind
        )
    }

    // MARK: - The arbitration gate (the actual Phase 1 fix)

    /// The gate in `TransactionHistoryViewModel` / `TransactionStatusPoller`
    /// skips native source-chain polling exactly when the registry resolves a
    /// service for the row. Without this, the native poller confirms the
    /// inbound deposit and marks a still-resting order `.successful`.
    func testRegistryResolvesThisServiceForALimitRow() {
        let registry = SwapTrackingRegistry()
        registry.register(Self.makeService(storage: FakeLimitTrackingStorage()))

        XCTAssertNotNil(registry.service(for: Self.makeLimitTx()))
    }

    /// Guards the regression this whole phase exists to fix: a limit row with
    /// no tracking metadata resolves no service, so the native poller stays
    /// authoritative and flips the order to Successful on deposit confirmation.
    func testRegistryResolvesNoServiceForALimitRowWithoutTrackingMetadata() {
        let registry = SwapTrackingRegistry()
        registry.register(Self.makeService(storage: FakeLimitTrackingStorage()))

        XCTAssertNil(registry.service(for: Self.makeLimitTx(includeTracking: false)))
    }

    /// A freshly-placed order has metadata but no recorded poll. It reads as
    /// `resting` — non-terminal, and the literal truth: it is sitting in the
    /// queue waiting for a price.
    func testAFreshlyPlacedLimitOrderIsNotTerminal() {
        let tx = Self.makeLimitTx()

        XCTAssertEqual(tx.swapTrackingUiStatus, .resting)
        XCTAssertFalse(tx.swapTrackingUiStatus.isTerminal)
    }

    // MARK: - Metadata factory

    /// The metadata the recording paths attach must be exactly what the gate
    /// dispatches on — the registry keys off `providerKind` alone.
    func testMetadataCarriesTheProviderKindTheRegistryDispatchesOn() {
        let metadata = THORChainLimitTrackingService.metadata(
            broadcastHash: "ABC123",
            sourceChain: .thorChain
        )

        XCTAssertEqual(metadata.providerKind, THORChainLimitTrackingService.providerKind)
        XCTAssertEqual(metadata.broadcastHash, "ABC123")
        XCTAssertEqual(metadata.sourceChainId, Chain.thorChain.rawValue)
    }

    /// A limit order is identified on-chain by its inbound tx hash — there is
    /// no aggregator-issued swap/route id, and inventing one would make the
    /// Phase 2 list-poll match on a field the protocol never returns.
    func testMetadataCarriesNoAggregatorIdentifiers() {
        let metadata = THORChainLimitTrackingService.metadata(
            broadcastHash: "ABC123",
            sourceChain: .thorChain
        )

        XCTAssertNil(metadata.swapId)
        XCTAssertNil(metadata.routeId)
        XCTAssertNil(metadata.subProvider)
    }

    /// A fresh order has been placed but never polled — it must not read as
    /// terminal, or the tracker would skip it and the row would stick.
    func testMetadataFromTheFactoryStartsNonTerminal() {
        let registry = SwapTrackingRegistry()
        registry.register(Self.makeService(storage: FakeLimitTrackingStorage()))
        let tx = Self.makeLimitTxCarrying(
            THORChainLimitTrackingService.metadata(broadcastHash: "ABC123", sourceChain: .thorChain)
        )

        XCTAssertNotNil(registry.service(for: tx), "factory metadata must resolve the gate")
        XCTAssertFalse(tx.swapTrackingUiStatus.isTerminal)
    }

    // MARK: - Ownership

    func testStartTakesOwnershipOfALimitRow() {
        let service = Self.makeService(storage: FakeLimitTrackingStorage())

        service.start(tx: Self.makeLimitTx())

        XCTAssertEqual(service.trackedOrderCountForTesting, 1)
        XCTAssertEqual(service.uiStatusByTxHash["limit-hash"], .resting)
    }

    func testStartIgnoresARowOwnedByAnotherProvider() {
        let service = Self.makeService(storage: FakeLimitTrackingStorage())

        service.start(tx: Self.makeLimitTx(providerKind: "swapKit"))

        XCTAssertEqual(service.trackedOrderCountForTesting, 0)
        XCTAssertTrue(service.uiStatusByTxHash.isEmpty)
    }

    func testStartIsIdempotentForTheSameRow() {
        let service = Self.makeService(storage: FakeLimitTrackingStorage())

        service.start(tx: Self.makeLimitTx())
        service.start(tx: Self.makeLimitTx())

        XCTAssertEqual(service.trackedOrderCountForTesting, 1)
    }

    /// A terminal row still gets its status seeded (so a view mounting on it
    /// renders correctly) but is never taken up for polling.
    func testStartSeedsButDoesNotTrackATerminalRow() {
        let service = Self.makeService(storage: FakeLimitTrackingStorage())

        service.start(tx: Self.makeLimitTx(latestTrackingStatus: "filled"))

        XCTAssertEqual(service.uiStatusByTxHash["limit-hash"], .completed)
        XCTAssertEqual(service.trackedOrderCountForTesting, 0)
    }

    func testStopReleasesTheRow() {
        let service = Self.makeService(storage: FakeLimitTrackingStorage())
        service.start(tx: Self.makeLimitTx())

        service.stop(txHash: "limit-hash")

        XCTAssertEqual(service.trackedOrderCountForTesting, 0)
    }

    func testStopIsIdempotent() {
        let service = Self.makeService(storage: FakeLimitTrackingStorage())

        service.stop(txHash: "never-tracked")

        XCTAssertEqual(service.trackedOrderCountForTesting, 0)
    }

    // MARK: - resumeInFlight

    func testResumeInFlightTakesUpOnlyThisProvidersNonTerminalRows() async {
        let storage = FakeLimitTrackingStorage()
        storage.inFlight = [
            Self.makeLimitTx(txHash: "limit-1"),
            Self.makeLimitTx(txHash: "limit-2"),
            Self.makeLimitTx(txHash: "swapkit-1", providerKind: "swapKit"),
            Self.makeLimitTx(txHash: "limit-done", latestTrackingStatus: "filled")
        ]
        let service = Self.makeService(storage: storage)

        await service.resumeInFlight()

        XCTAssertEqual(service.trackedOrderCountForTesting, 2)
    }

    func testResumeInFlightSurvivesAStorageFailure() async {
        let storage = FakeLimitTrackingStorage()
        storage.shouldThrowOnFetch = true
        let service = Self.makeService(storage: storage)

        await service.resumeInFlight()

        XCTAssertEqual(service.trackedOrderCountForTesting, 0)
    }

    // MARK: - ScenePhase

    func testSetActiveTogglesTheForegroundFlag() {
        let service = Self.makeService(storage: FakeLimitTrackingStorage())

        service.setActive(false)
        XCTAssertFalse(service.isActiveForTesting)

        service.setActive(true)
        XCTAssertTrue(service.isActiveForTesting)
    }

    // MARK: - Fixtures

    /// Builds the service with inert collaborators: these cases cover
    /// registration, ownership and lifecycle, not the poll loop (that's
    /// `THORChainLimitTrackingPollTests`). The inert HTTP client fails every
    /// request, so any poll a `start` kicks off just backs off — it never
    /// touches the network or reaches a conclusion.
    private static func makeService(storage: SwapTrackingStorage) -> THORChainLimitTrackingService {
        THORChainLimitTrackingService(
            httpClient: InertHTTPClient(),
            storage: storage,
            orders: InertLimitOrderObserver(),
            outcomes: InertOutcomeResolver()
        )
    }

    /// `includeTracking: false` models a row recorded *without* tracking
    /// metadata — the pre-fix behaviour. A nullable `swapTracking` parameter
    /// can't express this: `nil` would be indistinguishable from "use the
    /// default", so the no-metadata case would silently get metadata.
    /// Builds a row carrying exactly the given metadata — used to prove the
    /// production metadata factory's output satisfies the gate.
    private static func makeLimitTxCarrying(
        _ metadata: SwapTrackingMetadataData
    ) -> TransactionHistoryData {
        makeLimitTx(txHash: metadata.broadcastHash ?? "limit-hash", metadata: metadata)
    }

    private static func makeLimitTx(
        txHash: String = "limit-hash",
        providerKind: String = "thorchainLimit",
        latestTrackingStatus: String? = nil,
        includeTracking: Bool = true,
        metadata: SwapTrackingMetadataData? = nil
    ) -> TransactionHistoryData {
        TransactionHistoryData(
            id: UUID(),
            txHash: txHash,
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
            explorerLink: "https://runescan.io/tx/\(txHash)",
            createdAt: Date(),
            completedAt: nil,
            estimatedTime: nil,
            errorMessage: nil,
            swapTracking: includeTracking
                ? metadata ?? SwapTrackingMetadataData(
                    providerKind: providerKind,
                    swapId: nil,
                    routeId: nil,
                    broadcastHash: txHash,
                    sourceChainId: "THORChain",
                    subProvider: nil,
                    latestStatus: nil,
                    latestTrackingStatus: latestTrackingStatus
                )
                : nil
        )
    }
}

// MARK: - Fakes

private final class FakeLimitTrackingStorage: SwapTrackingStorage {
    var inFlight: [TransactionHistoryData] = []
    var shouldThrowOnFetch = false

    struct FetchError: Error {}

    // Phase 1 records no observations — the poll loop that would call these
    // lands in Phase 2, which will assert against them then.
    func updateSwapTrackingStatus(
        txHash _: String,
        pubKeyECDSA _: String,
        latestStatus _: String?,
        latestTrackingStatus _: String?,
        uiStatus _: SwapTrackingUiStatus,
        polledAt _: Date
    ) throws {}

    func touchSwapTrackingLastPolled(txHash _: String, pubKeyECDSA _: String, polledAt _: Date) throws {}

    func fetchInFlightSwapTracking(providerKind: String) throws -> [TransactionHistoryData] {
        if shouldThrowOnFetch { throw FetchError() }
        return inFlight
            .filter { $0.swapTracking?.providerKind == providerKind }
            .filter { !$0.swapTrackingUiStatus.isTerminal }
    }
}

/// Fails every request, so a poll started by these lifecycle tests backs off
/// instead of reaching the network or a conclusion.
private final class InertHTTPClient: HTTPClientProtocol {
    struct InertError: Error {}

    func request(_: TargetType) async throws -> HTTPResponse<Data> { // swiftlint:disable:this async_without_await
        throw InertError()
    }

    func requestEmpty(_: TargetType) async throws -> HTTPResponse<EmptyResponse> { // swiftlint:disable:this async_without_await
        throw InertError()
    }
}

@MainActor
private final class InertLimitOrderObserver: LimitOrderObserving {
    func recordObservation(
        inboundTxHash _: String,
        pubKeyECDSA _: String,
        status _: LimitOrderStatus,
        depositAmount _: String?,
        filledInAmount _: String?,
        filledOutAmount _: String?,
        observedTradeTarget _: String?,
        timeToExpiryBlocks _: Int?
    ) throws {}
}

@MainActor
private final class InertOutcomeResolver: LimitOrderOutcomeResolving {
    func resolveOutcome(inboundTxHash _: String, sourceChain _: Chain) async -> LimitOrderOutcome { // swiftlint:disable:this async_without_await
        .unresolved
    }
}
