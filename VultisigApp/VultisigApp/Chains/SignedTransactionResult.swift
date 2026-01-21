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
    case regularWithApprove(approve: SignedTransactionResult, transaction: SignedTransactionResult)

    /// NOTE: Approve transaction should be first
    init?(transactions: [SignedTransactionResult]) {
        if transactions.count == 2 {
            self = .regularWithApprove(approve: transactions[0], transaction: transactions[1])
            return
        }

        if transactions.count == 1 {
            self = .regular(transactions[0])
            return
        }

        return nil
    }

    var transactionHash: String {
        switch self {
        case .regular(let transaction):
            return transaction.transactionHash
        case .regularWithApprove(_, let transaction):
            return transaction.transactionHash
        }
    }

    var approveTransactionHash: String? {
        switch self {
        case .regular:
            return nil
        case .regularWithApprove(let approve, _):
            return approve.transactionHash
        }
    }
}
