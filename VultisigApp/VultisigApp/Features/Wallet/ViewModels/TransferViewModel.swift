//
//  SendViewModel.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 10.04.2024.
//

import Foundation

@MainActor protocol TransferViewModel: AnyObject {
    var hash: String? { get set }
    var approveHash: String? { get set }
    func moveToNextView()
    func retryBroadcast(reason: BroadcastRetryReason)
    /// Hands the keysign screen's resolved (possibly bootstrap-refreshed)
    /// payload to the coordinator so the done route shows the SIGNED payload.
    /// A protocol requirement (not just an extension method) so the override
    /// dispatches dynamically through the existential; defaulted to a no-op for
    /// the consumers that don't need it (custom message).
    func updateResolvedKeysignPayload(_ payload: KeysignPayload?)
}

extension TransferViewModel {
    func retryBroadcast(reason _: BroadcastRetryReason) {}
    func updateResolvedKeysignPayload(_: KeysignPayload?) {}
}
