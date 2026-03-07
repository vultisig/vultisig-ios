//
//  TransactionHistoryTab.swift
//  VultisigApp
//

import Foundation

enum TransactionHistoryTab: String, CaseIterable, Hashable {
    case overview
    case swaps
    case send

    var title: String {
        switch self {
        case .overview:
            return "overview".localized
        case .swaps:
            return "swaps".localized
        case .send:
            return "send".localized
        }
    }
}
