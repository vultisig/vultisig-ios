//
//  DoneStatusService.swift
//  VultisigApp
//
//  Single ObservableObject the `DoneScreen` binds to. Holds the current
//  `TransactionStatus` published to the view and forwards the
//  start/stop lifecycle to an injected `DoneStatusPoller`. The
//  poller does the actual chain-RPC / `/track` work; this layer is a
//  thin forwarder so the view never has to know which polling backend
//  is wired.
//
//  Routing — "send vs swap vs cosigner vs signed-message" — lives in
//  `DoneStatusServiceFactory`. New backends land by adding a
//  poller conformer and a factory entry; the service and view stay
//  untouched.
//

import Foundation
import SwiftUI

/// Backend abstraction for the live transaction-status header on the
/// done screen. One conformer per polling strategy.
@MainActor
protocol DoneStatusPoller {
    /// Seed status surfaced before `start()` runs (or for back-ends that
    /// never poll). Reading this in `DoneStatusService.init`
    /// avoids a flash of empty state before the first poll lands.
    var initialStatus: TransactionStatus { get }

    /// Begin the polling work. Idempotent — safe to call from
    /// `onAppear` on a view that may already be live.
    func start(onStatus: @escaping (TransactionStatus) -> Void)

    /// Cancel the polling work. Idempotent — safe to call from
    /// `onDisappear`.
    func stop()
}

@MainActor
final class DoneStatusService: ObservableObject {
    @Published private(set) var status: TransactionStatus

    private let poller: any DoneStatusPoller

    init(poller: any DoneStatusPoller) {
        self.poller = poller
        self.status = poller.initialStatus
    }

    func start() {
        poller.start { [weak self] newStatus in
            self?.status = newStatus
        }
    }

    func stop() {
        poller.stop()
    }
}
