//
//  TransactionMemoTypeEnum.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import SwiftUI
import Foundation
import Combine

enum TransactionMemoType: String, CaseIterable, Identifiable {
    case bond, unbond, leave, custom, vote, addPool, withdrawPool
    
    var id: String { self.rawValue }
    var display: String {
        switch self {
        case .bond:
            return "Bond"
        case .unbond:
            return "Unbond"
        case .leave:
            return "Leave"
        case .custom:
            return "Custom"
        case .addPool:
            return "Add to RUNEPool"
        case .withdrawPool:
            return "Remove from RUNEPool"
        case .vote:
            return "Vote"
        }
    }
    
    static func getCases(for coin: Coin) -> [TransactionMemoType] {
        switch coin.chain {
        case .thorChain, .mayaChain:
            return [.bond, .unbond, .leave, .custom, .addPool, .withdrawPool]
        case .dydx:
            return [.vote]
        default:
            return []
        }
    }
    
    static func getDefault(for coin: Coin) -> TransactionMemoType {
        switch coin.chain {
        case .thorChain, .mayaChain:
            return .bond
        case .dydx:
            return .vote
        default:
            return .custom
        }
    }
}
