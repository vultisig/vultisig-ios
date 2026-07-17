//
//  ForegroundNotificationData.swift
//  VultisigApp
//

import Foundation
import SwiftUI

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

    var iconName: ImageResource {
        switch transactionType {
        case .swap:
            return .repeatLeftRight
        case .send:
            return .arrowUpFromLine
        case .generic:
            return .bell
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
