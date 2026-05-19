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

    var broadcastedKey: String {
        switch self {
        case .send: return "transactionBroadcasted"
        case .claim: return "claimBroadcasted"
        }
    }

    var pendingKey: String {
        switch self {
        case .send: return "transactionPending"
        case .claim: return "claimPending"
        }
    }

    var successfulKey: String {
        switch self {
        case .send: return "transactionSuccessful"
        case .claim: return "claimSuccessful"
        }
    }

    var failedKey: String {
        switch self {
        case .send: return "transactionFailed"
        case .claim: return "claimFailed"
        }
    }
}
