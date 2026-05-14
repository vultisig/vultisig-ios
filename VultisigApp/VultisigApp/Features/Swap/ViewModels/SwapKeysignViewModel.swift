//
//  SwapKeysignViewModel.swift
//  VultisigApp
//

import Foundation
import Mediator

@MainActor
@Observable
final class SwapKeysignViewModel: TransferViewModel {
    var keysignFinished: Bool = false

    var hash: String?
    var approveHash: String?

    @ObservationIgnored private let retrySignal: SwapRetrySignal

    init(retrySignal: SwapRetrySignal) {
        self.retrySignal = retrySignal
    }

    func moveToNextView() {
        keysignFinished = true
    }

    func retryBroadcast(reason: BroadcastRetryReason) {
        retrySignal.pendingRetryReason = reason
    }

    func stopMediator() {
        Mediator.shared.stop()
    }
}
