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

    var title: String {
        return rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .send:
            return .turquoise600
        case .swap:
            return .persianBlue200
        case .deposit, .bridge:
            return .mediumPurple
        }
    }
}
