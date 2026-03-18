//
//  ForegroundNotificationData.swift
//  VultisigApp
//

import Foundation

struct ForegroundNotificationData: Equatable {
    enum TransactionType: Equatable {
        case swap(description: String)
        case send(description: String)
        case generic(body: String)
    }

    let transactionType: TransactionType
    let vaultName: String
    let isFastVault: Bool
    let deeplinkURL: URL

    var iconName: String {
        switch transactionType {
        case .swap:
            return "repeat-left-right"
        case .send:
            return "arrow-up-from-dot"
        case .generic:
            return "bell"
        }
    }

    var description: String {
        switch transactionType {
        case .swap(let description):
            return description
        case .send(let description):
            return description
        case .generic(let body):
            return body
        }
    }
}
