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
    
    var title: String {
        return rawValue.capitalized
    }
    
    var color: Color {
        switch self {
        case .send:
            return Theme.colors.bgButtonPrimary
        case .swap:
            return Theme.colors.primaryAccent4
        case .deposit, .bridge, .memo,.buy,.sell:
            return Theme.colors.primaryAccent3
        }
    }
}
