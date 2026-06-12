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

    var broadcastedKey: String {
        switch self {
        case .send: return "transactionBroadcasted"
        case .claim: return "claimBroadcasted"
        case .sign: return "messageSigned"
        }
    }

    var pendingKey: String {
        switch self {
        case .send: return "transactionPending"
        case .claim: return "claimPending"
        case .sign: return "messageSigned"
        }
    }

    var successfulKey: String {
        switch self {
        case .send: return "transactionSuccessful"
        case .claim: return "claimSuccessful"
        case .sign: return "messageSigned"
        }
    }

    var failedKey: String {
        switch self {
        case .send: return "transactionFailed"
        case .claim: return "claimFailed"
        case .sign: return "messageSignFailed"
        }
    }
}
