//
//  SwapMode.swift
//  VultisigApp
//
//  The swap-screen mode tabs. Market is the only executable mode today; Limit
//  is surfaced in the UI per design but its order-execution is out of scope.
//

import Foundation

enum SwapMode: CaseIterable, Identifiable {
    case market
    case limit

    var id: Self { self }

    var title: String {
        switch self {
        case .market:
            return "swapModeMarket".localized
        case .limit:
            return "swapModeLimit".localized
        }
    }
}
