//
//  TransactionHistoryTab.swift
//  VultisigApp
//

import Foundation

/// Declaration order IS tab order — `TransactionHistoryScreen` builds the
/// segmented control straight from `allCases`, so `limitOrders` sits between
/// `swaps` and `send` to match the design.
enum TransactionHistoryTab: String, CaseIterable, Hashable {
    case overview
    case swaps
    case limitOrders
    case send

    var title: String {
        switch self {
        case .overview:
            return "overview".localized
        case .swaps:
            return "swaps".localized
        case .limitOrders:
            // Same string the swap done-screen banner already promises the
            // user they'll find here.
            return "limitSwap.done.bannerTitle".localized
        case .send:
            return "send".localized
        }
    }
}
