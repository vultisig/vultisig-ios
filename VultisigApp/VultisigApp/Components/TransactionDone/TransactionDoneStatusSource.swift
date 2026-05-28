//
//  TransactionDoneStatusSource.swift
//  VultisigApp
//
//  Protocol seam between `TransactionDoneView` and the polling
//  back-ends that drive its status header. Three concrete sources:
//
//  - `ChainPollerStatusSource` — wraps `TransactionStatusViewModel`'s
//    per-chain RPC poller. Used by Send, QBTC claim, and the
//    non-SwapKit swap routes.
//  - `SwapKitStatusSource` — drives status off
//    `SwapKitTrackingService.shared`'s `/track` poll, because the
//    native per-chain RPC poller races the cross-chain leg for
//    SwapKit-routed swaps and surfaces a premature "successful" once
//    the source tx confirms.
//  - `StaticStatusSource` — never polls; emits a single fixed status.
//    Used by the keysign-cosigner path when no tx hash is available
//    (peer can't poll without an identity for the poll), and as the
//    default for previews/tests.
//

import Foundation
import SwiftUI

@MainActor
protocol TransactionDoneStatusSource: ObservableObject {
    /// Current status surfaced by the header. Updates are observed via
    /// the conformer's `@Published` / `objectWillChange` machinery.
    var status: TransactionStatus { get }

    /// Begin polling. Idempotent — safe to call from `.onAppear` on a
    /// view that may already be live.
    func start()

    /// Stop polling. Idempotent — safe to call from `.onDisappear`.
    func stop()
}

// MARK: - ChainPollerStatusSource

/// Wraps `TransactionStatusViewModel` so the chain-poller can be passed
/// behind the `TransactionDoneStatusSource` protocol without
/// `TransactionDoneView` knowing about the concrete VM.
@MainActor
final class ChainPollerStatusSource: TransactionDoneStatusSource {
    @Published private(set) var status: TransactionStatus

    private let viewModel: TransactionStatusViewModel
    private var observationTask: Task<Void, Never>?

    init(
        txHash: String,
        chain: Chain,
        coinTicker: String?,
        amount: String?,
        toAddress: String?,
        pubKeyECDSA: String?
    ) {
        let viewModel = TransactionStatusViewModel(
            txHash: txHash,
            chain: chain,
            coinTicker: coinTicker,
            amount: amount,
            toAddress: toAddress,
            pubKeyECDSA: pubKeyECDSA
        )
        self.viewModel = viewModel
        self.status = viewModel.status
    }

    func start() {
        guard observationTask == nil else { return }
        viewModel.startPolling()
        observationTask = Task { [weak self] in
            guard let self else { return }
            for await newStatus in self.viewModel.$status.values {
                self.status = newStatus
            }
        }
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
        viewModel.stopPolling()
    }
}

// MARK: - StaticStatusSource

/// Emits a single fixed status. Used by the keysign-cosigner path when
/// the peer has no broadcast-side identity to poll against, and for
/// previews/tests.
@MainActor
final class StaticStatusSource: TransactionDoneStatusSource {
    @Published private(set) var status: TransactionStatus

    init(status: TransactionStatus = .confirmed) {
        self.status = status
    }

    func start() {}
    func stop() {}
}

// MARK: - AnyTransactionDoneStatusSourceBox

/// Type-erased wrapper so callers (e.g. `SwapDoneScreen`) can pick
/// between concrete sources at runtime and still hand a single concrete
/// `@ObservedObject` type to `DoneScreen`. Forwards `status` /
/// `start()` / `stop()` to the boxed source and re-publishes changes.
@MainActor
final class AnyTransactionDoneStatusSourceBox: TransactionDoneStatusSource {
    @Published private(set) var status: TransactionStatus

    private let startBox: () -> Void
    private let stopBox: () -> Void
    private let currentStatus: () -> TransactionStatus
    private let observe: (@escaping () -> Void) -> Task<Void, Never>
    private var observationTask: Task<Void, Never>?

    init<Source: TransactionDoneStatusSource>(source: Source) {
        self.status = source.status
        self.startBox = { source.start() }
        self.stopBox = { source.stop() }
        self.currentStatus = { source.status }
        self.observe = { onChange in
            Task { @MainActor in
                for await _ in source.objectWillChange.values {
                    // `objectWillChange` fires *before* the `@Published`
                    // setter commits, so reading `source.status` from
                    // inside `onChange()` would observe the pre-mutation
                    // value and lag by one tick. Yield to the runloop so
                    // the next read sees the committed status.
                    await Task.yield()
                    onChange()
                }
            }
        }
    }

    func start() {
        bindIfNeeded()
        startBox()
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
        stopBox()
    }

    private func bindIfNeeded() {
        guard observationTask == nil else { return }
        observationTask = observe { [weak self] in
            guard let self else { return }
            self.status = self.currentStatus()
        }
    }
}
