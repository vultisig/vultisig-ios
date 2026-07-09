//
//  SigningKeysignCoordinator.swift
//  VultisigApp
//
//  One coordinator behind the unified `SigningKeysignScreen`, folding the
//  former per-flow `SendKeysignViewModel` + `SwapKeysignViewModel`. It is the
//  `TransferViewModel` handed to `KeysignView`: the ceremony writes the hash /
//  approve-hash / resolved payload here and calls `moveToNextView()`, and a
//  retryable broadcast failure calls `retryBroadcast(reason:)`. The owning
//  screen watches `keysignFinished` (build the done route) and
//  `pendingRetryReason` (pop to verify), and calls `stopMediator()` for swaps.
//

import Foundation
import Mediator

@MainActor
final class SigningKeysignCoordinator: ObservableObject, TransferViewModel {
    /// Flips once the ceremony has a broadcastable result; the screen reads
    /// `hash` / `approveHash` / `resolvedKeysignPayload` (all set first) and
    /// navigates to the flow's done screen.
    @Published var keysignFinished: Bool = false
    /// Set by a retryable broadcast failure; the screen threads it back to the
    /// flow's retry signal and pops to verify, then clears it.
    @Published var pendingRetryReason: BroadcastRetryReason?

    var hash: String?
    var approveHash: String?

    /// The payload the ceremony actually signed. For fast vaults the bootstrap
    /// can replace it before signing (e.g. Solana blockhash refresh), so the
    /// send-family done route must read THIS rather than the route's original
    /// payload — replacing the old `onKeysignInputResolved` callback.
    private(set) var resolvedKeysignPayload: KeysignPayload?

    func moveToNextView() {
        keysignFinished = true
    }

    func retryBroadcast(reason: BroadcastRetryReason) {
        pendingRetryReason = reason
    }

    func updateResolvedKeysignPayload(_ payload: KeysignPayload?) {
        resolvedKeysignPayload = payload
    }

    func stopMediator() {
        Mediator.shared.stop()
    }
}
