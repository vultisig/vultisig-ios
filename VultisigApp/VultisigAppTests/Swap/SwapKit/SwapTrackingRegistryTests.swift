//
//  SwapTrackingRegistryTests.swift
//  VultisigAppTests
//
//  Registry coverage for `SwapTrackingRegistry` — the per-row dispatcher
//  that maps `SwapTrackingMetadata.providerKind` to the registered
//  `SwapTrackingService` conformer. The tx-history viewmodel and the
//  native status poller both lean on this lookup to decide whether a
//  row's status comes from a tracker or from native chain polling.
//
//  Tests instantiate a fresh `SwapTrackingRegistry` per case (via the
//  exposed test initializer) so they don't depend on the order in which
//  app-startup registrations land in `SwapTrackingRegistry.shared`.
//

import XCTest
@testable import VultisigApp

@MainActor
final class SwapTrackingRegistryTests: XCTestCase {

    func testRegisterStoresServiceByProviderKind() {
        let registry = SwapTrackingRegistry()
        let service = FakeSwapKitService()

        registry.register(service)

        XCTAssertEqual(registry.registeredCountForTesting, 1)
    }

    func testRegisterIsIdempotentForSameProviderKind() {
        let registry = SwapTrackingRegistry()
        let first = FakeSwapKitService()
        let second = FakeSwapKitService()

        registry.register(first)
        registry.register(second)

        XCTAssertEqual(registry.registeredCountForTesting, 1,
                       "Re-registering the same providerKind must overwrite, not duplicate")
    }

    func testServiceLookupByRowReturnsRegisteredConformer() {
        let registry = SwapTrackingRegistry()
        let service = FakeSwapKitService()
        registry.register(service)

        let tx = Self.makeRow(providerKind: "swapKit")

        XCTAssertTrue(registry.service(for: tx) === service,
                      "Lookup must return the exact registered instance for a matching providerKind")
    }

    func testServiceLookupReturnsNilForUnknownProviderKind() {
        let registry = SwapTrackingRegistry()
        registry.register(FakeSwapKitService())

        let tx = Self.makeRow(providerKind: "chainflip")

        XCTAssertNil(registry.service(for: tx),
                     "Unknown providerKind must not match any registered service")
    }

    func testServiceLookupReturnsNilForUntrackedRow() {
        let registry = SwapTrackingRegistry()
        registry.register(FakeSwapKitService())

        let tx = Self.makeRow(providerKind: nil)

        XCTAssertNil(registry.service(for: tx),
                     "Rows with no swapTracking metadata must look up to nil")
    }

    func testMultipleProvidersCoexistInRegistry() {
        let registry = SwapTrackingRegistry()
        let swapKit = FakeSwapKitService()
        let chainflip = FakeChainflipService()
        registry.register(swapKit)
        registry.register(chainflip)

        XCTAssertEqual(registry.registeredCountForTesting, 2)
        XCTAssertTrue(registry.service(for: Self.makeRow(providerKind: "swapKit")) === swapKit)
        XCTAssertTrue(registry.service(for: Self.makeRow(providerKind: "chainflip")) === chainflip)
    }

    // MARK: - Fixtures

    private static func makeRow(providerKind: String?) -> TransactionHistoryData {
        TransactionHistoryData(
            id: UUID(),
            txHash: "0xreg-\(UUID().uuidString)",
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
            swapProvider: providerKind,
            feeCrypto: "0.01",
            feeFiat: "20",
            network: "Ethereum",
            explorerLink: "https://etherscan.io/tx/x",
            createdAt: Date(),
            completedAt: nil,
            estimatedTime: nil,
            errorMessage: nil,
            swapTracking: providerKind.map {
                SwapTrackingMetadataData(
                    providerKind: $0,
                    broadcastHash: "0xbroadcast",
                    sourceChainId: "1"
                )
            }
        )
    }
}

// MARK: - Fakes

/// `SwapTrackingService` conformer that pins `providerKind` at compile time.
/// One class per kind avoids the static-state pitfall of trying to make a
/// configurable stub (the registry calls `type(of:)` to read the kind, so
/// every instance of a single class resolves to the same value).
@MainActor
private final class FakeSwapKitService: SwapTrackingService {
    static var providerKind: String { "swapKit" }
    var uiStatusByTxHash: [String: SwapTrackingUiStatus] = [:]
    func start(tx: TransactionHistoryData) {}
    func stop(txHash: String) {}
    func resumeInFlight() async {}
    func setActive(_ active: Bool) {}
}

@MainActor
private final class FakeChainflipService: SwapTrackingService {
    static var providerKind: String { "chainflip" }
    var uiStatusByTxHash: [String: SwapTrackingUiStatus] = [:]
    func start(tx: TransactionHistoryData) {}
    func stop(txHash: String) {}
    func resumeInFlight() async {}
    func setActive(_ active: Bool) {}
}
