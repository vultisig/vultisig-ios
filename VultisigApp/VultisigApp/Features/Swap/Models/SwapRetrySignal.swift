//
//  SwapRetrySignal.swift
//  VultisigApp
//
//  Single-purpose flow signal between Keysign (writer) and Verify (reader).
//  Replaces the old SwapDraftStore.pendingRetryReason side-channel — kept
//  small because that's the only cross-screen mutable state that survives
//  the SwapDraftStore deletion.
//
//  Verify constructs one when navigating to the verify route; the same
//  reference threads forward through Pair/Keysign so a retryable broadcast
//  failure can flag back to Verify on pop.
//

import Foundation

@Observable
final class SwapRetrySignal: Hashable {
    var pendingRetryReason: BroadcastRetryReason?

    init() {}

    static func == (lhs: SwapRetrySignal, rhs: SwapRetrySignal) -> Bool {
        lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
