//
//  TransactionActionVerb.swift
//  VultisigApp
//
//  Verb used by the shared done-screen primitives
//  (`TransactionStatusHeaderView`, `SendCryptoDoneHeaderView`,
//  `SendCryptoDoneContentView`) so QBTC claim can render the same
//  done screen as Send/Swap with "Claim" copy instead of "Transaction"
//  copy. Default `.send` preserves every existing caller's behavior.
//

import Foundation

enum TransactionActionVerb: Hashable {
    case send
    case claim
    /// Custom-message signing flow — the dApp asked the user to sign
    /// a message, not broadcast a transaction. There's no chain status
    /// to poll, so all four states resolve to the same "Message signed"
    /// copy.
    case sign
    /// THORChain limit (`=<`) order. A placed order does not "succeed" when
    /// the inbound deposit confirms — it comes to REST, possibly for days,
    /// until the price is met. The generic transaction copy would call that
    /// "Transaction successful", which is the single most visible lie this
    /// flow can tell, so the whole vocabulary is re-cast in terms of the
    /// order: submitted → placed (resting) → filled, or not filled.
    case limitOrder

    var broadcastedKey: String {
        switch self {
        case .send: return "transactionBroadcasted"
        case .claim: return "claimBroadcasted"
        case .sign: return "messageSigned"
        case .limitOrder: return "limitSwap.done.status.submitted"
        }
    }

    var pendingKey: String {
        switch self {
        case .send: return "transactionPending"
        case .claim: return "claimPending"
        case .sign: return "messageSigned"
        case .limitOrder: return "limitSwap.done.status.resting"
        }
    }

    var successfulKey: String {
        switch self {
        case .send: return "transactionSuccessful"
        case .claim: return "claimSuccessful"
        case .sign: return "messageSigned"
        case .limitOrder: return "limitSwap.done.status.filled"
        }
    }

    var failedKey: String {
        switch self {
        case .send: return "transactionFailed"
        case .claim: return "claimFailed"
        case .sign: return "messageSignFailed"
        case .limitOrder: return "limitSwap.done.status.notFilled"
        }
    }

    /// Substring of `successfulKey` the header paints with the brand gradient.
    /// Per-verb because the emphasis has to be a word that actually occurs in
    /// that verb's sentence — highlighting "successful" inside "Order filled"
    /// silently matches nothing and drops the accent.
    var successfulHighlightKey: String {
        switch self {
        case .send, .claim, .sign: return "transactionSuccessfulHighlight"
        case .limitOrder: return "limitSwap.done.status.filledHighlight"
        }
    }

    /// Substring of `failedKey` the header paints in the error color.
    var failedHighlightKey: String {
        switch self {
        case .send, .claim, .sign: return "transactionFailedHighlight"
        case .limitOrder: return "limitSwap.done.status.notFilledHighlight"
        }
    }

    /// Sub-copy under the status title, for states that need a sentence the
    /// title can't carry. `nil` — the default — leaves the header exactly as
    /// it was for every pre-existing verb.
    ///
    /// `.failed` is deliberately absent: that branch already renders the
    /// reason carried on the status itself, which is more specific than
    /// anything a verb could say.
    func detailKey(for status: TransactionStatus) -> String? {
        switch (self, status) {
        case (.limitOrder, .pending):
            // The one line that stops "Order placed" reading as "done".
            return "limitSwap.done.status.restingDetail"
        default:
            return nil
        }
    }
}
