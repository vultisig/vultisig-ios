//
//  NoPoller.swift
//  VultisigApp
//
//  `DoneStatusPoller` that never polls. Emits a single fixed
//  status seeded at construction. Used by the custom-message signing
//  flow (no on-chain tx to track) and as the default for previews /
//  tests.
//

import Foundation

@MainActor
final class NoPoller: DoneStatusPoller {
    let initialStatus: TransactionStatus

    init(initialStatus: TransactionStatus = .confirmed) {
        self.initialStatus = initialStatus
    }

    func start(onStatus _: @escaping (TransactionStatus) -> Void) {}
    func stop() {}
}
