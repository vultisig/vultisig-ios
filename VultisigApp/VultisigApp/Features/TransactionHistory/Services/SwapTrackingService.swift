//
//  SwapTrackingService.swift
//  VultisigApp
//
//  Provider-agnostic surface for swap-aggregator tracking. Each concrete
//  conformer owns the lifecycle of polling for rows whose
//  `SwapTrackingMetadata.providerKind` matches its `providerKind`.
//
//  Today only `SwapKitTrackingService` registers; future aggregators (a
//  dedicated Chainflip integration, additional THORChain extensions,
//  alternate API providers) plug in here without touching the tx-history
//  storage schema or the viewmodel.
//

import Foundation

@MainActor
protocol SwapTrackingService: AnyObject {
    /// Discriminator matched against `SwapTrackingMetadata.providerKind`.
    /// Static so the registry can dispatch without an instance.
    /// `nonisolated` so non-MainActor callers (e.g. value-type extensions
    /// on `TransactionHistoryData`) can read it without an actor hop.
    nonisolated static var providerKind: String { get }

    /// Latest UI status per `txHash`. Observable so views can subscribe.
    /// Concrete types expose this as `@Published`.
    var uiStatusByTxHash: [String: SwapTrackingUiStatus] { get }

    /// Begin polling this row. No-op if already polling or row is terminal
    /// or the row isn't owned by this provider.
    func start(tx: TransactionHistoryData)

    /// Resume polling for every non-terminal row matching this provider.
    /// Called at app launch and on scene-active.
    func resumeInFlight() async

    /// Toggle the global active flag — pauses polling when the app is
    /// backgrounded, resumes when it returns to foreground.
    func setActive(_ active: Bool)

    /// Hard-stop tracking for EVERY row this provider owns and drop all
    /// in-memory tracking state. Unlike `setActive(false)` — which cancels the
    /// running tasks but keeps the registry so foreground can resume — this is
    /// a teardown with nothing to resume from. Used by the global "Reset
    /// Transaction History" action, which deletes the rows these tasks would
    /// otherwise keep polling (and writing back into).
    func stopAllTracking()
}
