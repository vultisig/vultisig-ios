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
    case bond, unbond, bondMaya, unbondMaya, leave, custom, vote, stake, unstake, addPool, removePool, cosmosIBC, merge
    
    var id: String { self.rawValue }
    
    func display(coin: Coin) -> String {
        switch self {
        case .bond:
            if coin.chain == .mayaChain {
                return "Add Bondprovider to WL"
            }
            return "Bond"
        case .unbond:
            if coin.chain == .mayaChain {
                return "Remove Bondprovider from WL"
            }
            return "Unbond"
        case .bondMaya:
            return "Bond"
        case .unbondMaya:
            return "Unbond"
        case .addPool:
            return "Add Pool"
        case .removePool:
            return "Remove Pool"
        case .leave:
            return "Leave"
        case .custom:
            return "Custom"
        case .vote:
            return "Vote"
        case .stake:
            return "Stake"
        case .unstake:
            return "Unstake"
        case .cosmosIBC:
            return "IBC Transfer"
        case .merge:
            return "The Merge"
        }
    }
    
    static func getCases(for coin: Coin) -> [TransactionMemoType] {
        switch coin.chain {
        case .thorChain:
            return [.bond, .unbond, .leave, .merge, .custom]
        case .mayaChain:
            return [.bondMaya, .unbondMaya, .leave, .custom, .addPool, .removePool]
        case .dydx:
            return [.vote]
        case .ton:
            return [.stake, .unstake]
        case .gaiaChain, .kujira, .osmosis, .noble, .akash:
            return [.cosmosIBC]
        default:
            return []
        }
    }
    
    static func getDefault(for coin: Coin) -> TransactionMemoType {
        switch coin.chain {
        case .thorChain:
            return .bond
        case .mayaChain:
            return .bondMaya
        case .dydx:
            return .vote
        case .ton:
            return .stake
        default:
            return .custom
        }
    }
}
