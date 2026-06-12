//
//  SwapTrackingRegistry.swift
//  VultisigApp
//
//  Registry of `SwapTrackingService` conformers. Keyed by
//  `providerKind` (the same discriminator stored on
//  `SwapTrackingMetadata`). The tx-history viewmodel and the native
//  status poller resolve "is this row owned by a tracking service?" by
//  asking the registry, so new providers slot in without changes to
//  either consumer.
//

import Foundation

@MainActor
final class SwapTrackingRegistry {
    static let shared = SwapTrackingRegistry()

    private var services: [String: any SwapTrackingService] = [:]

    /// Test-only — production uses `shared`. Allows tests to spin up an
    /// isolated registry without leaking state into other test cases.
    init() {}

    /// Register a tracking service. Idempotent — re-registering the same
    /// `providerKind` overwrites the previous entry. Called once per
    /// conformer at app startup.
    func register(_ service: any SwapTrackingService) {
        services[type(of: service).providerKind] = service
    }

    /// The service that owns `tx`, or `nil` if `tx` has no tracking metadata
    /// or its `providerKind` doesn't match any registered service.
    func service(for tx: TransactionHistoryData) -> (any SwapTrackingService)? {
        guard let kind = tx.swapTracking?.providerKind else { return nil }
        return services[kind]
    }

    /// Resume polling on every registered service. Called at app launch and
    /// on scene-active so each provider walks its own non-terminal rows.
    func resumeAllInFlight() async {
        for service in services.values {
            await service.resumeInFlight()
        }
    }

    /// Toggle the active flag on every registered service.
    func setActiveOnAll(_ active: Bool) {
        for service in services.values {
            service.setActive(active)
        }
    }

    /// Test-only — drop every registered service so test cases start clean.
    func removeAllForTesting() {
        services.removeAll()
    }

    /// Test-only — count of currently-registered services.
    var registeredCountForTesting: Int { services.count }
}
