//
//  SwapKeysignViewModel.swift
//  VultisigApp
//

import Foundation
import Mediator

@MainActor
final class SwapKeysignViewModel: ObservableObject, TransferViewModel {
    @Published var keysignFinished: Bool = false
    @Published var pendingRetryReason: BroadcastRetryReason?

    var hash: String?
    var approveHash: String?

    func moveToNextView() {
        keysignFinished = true
    }

    func retryBroadcast(reason: BroadcastRetryReason) {
        pendingRetryReason = reason
    }

    func stopMediator() {
        Mediator.shared.stop()
    }
}
