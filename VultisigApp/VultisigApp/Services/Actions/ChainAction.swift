//
//  DepositOption.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 01.05.2024.
//

import SwiftUI

enum CoinAction: String, Codable {
    case send
    case swap
    case deposit
    case bridge
    case memo
    case buy
    case sell
    case receive

    var title: String {
        return rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .send:
            return Theme.colors.bgButtonPrimary
        case .swap:
            return Theme.colors.primaryAccent4
        case .deposit, .bridge, .memo, .buy, .sell, .receive:
            return Theme.colors.primaryAccent3
        }
    }

    var buttonTitle: String {
        switch self {
        case .send:
            "send".localized
        case .swap:
            "swap".localized
        case .deposit, .bridge, .memo:
            "function".localized
        case .buy:
            "buy".localized
        case .sell:
            "sell".localized
        case .receive:
            "receive".localized
        }
    }

    var buttonIcon: String {
        switch self {
        case .send:
            "arrow-up-right-1"
        case .swap:
            "arrow-left-right"
        case .deposit:
            "action"
        case .bridge:
            "action"
        case .memo:
            "action"
        case .buy:
            "shopping-bag-add"
        case .sell:
            "shopping-bag-add"
        case .receive:
            "arrow-wall-down"
        }
    }

    var shouldHightlight: Bool {
        switch self {
        case .swap:
            return true
        case .send,
                .deposit,
                .bridge,
                .memo,
                .buy,
                .sell,
                .receive:
            return false
        }
    }

    var isDefi: Bool {
        switch self {
        case .deposit, .bridge, .memo:
            return true
        case .send, .swap, .buy, .sell, .receive:
            return false
        }
    }
}
