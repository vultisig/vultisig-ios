//
//  SendRetrySignal.swift
//  VultisigApp
//
//  Single-purpose flow signal between Keysign (writer) and Verify (reader).
//  Replaces the legacy `LegacySendTransaction.pendingRetryReason` side-channel
//  — that field stops surviving the form-state rewrite (Phase B step 5), so
//  the retry intent gets its own tiny @Observable holder that threads through
//  the `verify → pair → keysign` route value sequence.
//
//  Mirrors `SwapRetrySignal`.
//

import Foundation

@Observable
final class SendRetrySignal: Hashable {
    var pendingRetryReason: BroadcastRetryReason?

    init() {}

    static func == (lhs: SendRetrySignal, rhs: SendRetrySignal) -> Bool {
        lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
