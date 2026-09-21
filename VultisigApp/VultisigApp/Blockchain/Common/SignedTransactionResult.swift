//
//  SignedTransactionResult.swift
//  VultisigApp
//
//  Created by Johnny Luo on 19/4/2024.
//

import Foundation

struct SignedTransactionResult {
    let rawTransaction: String
    let transactionHash: String
    var signature: String?
}

enum SignedTransactionType {
    case regular(SignedTransactionResult)
    /// The ERC20 approve legs in nonce order, then the transaction that spends
    /// the allowance. With an allowance reset the legs are `approve(0)`, then
    /// `approve(amount)`.
    case regularWithApprove(approves: [SignedTransactionResult], transaction: SignedTransactionResult)

    /// The last result is the transaction and every one before it is an
    /// approve leg, in nonce order. Only an empty list yields nil, which sends
    /// the caller on to the per-chain helpers: a signed swap must never be
    /// re-built there as a plain transfer.
    init?(transactions: [SignedTransactionResult]) {
        guard let transaction = transactions.last else {
            return nil
        }
        let approves = Array(transactions.dropLast())
        if approves.isEmpty {
            self = .regular(transaction)
        } else {
            self = .regularWithApprove(approves: approves, transaction: transaction)
        }
    }

    var transactionHash: String {
        switch self {
        case .regular(let transaction):
            return transaction.transactionHash
        case .regularWithApprove(_, let transaction):
            return transaction.transactionHash
        }
    }

    /// The approve that grants the allowance: the last leg, `approve(amount)`.
    /// A preceding `approve(0)` reset is broadcast but never surfaced.
    var approveTransactionHash: String? {
        switch self {
        case .regular:
            return nil
        case .regularWithApprove(let approves, _):
            return approves.last?.transactionHash
        }
    }
}
