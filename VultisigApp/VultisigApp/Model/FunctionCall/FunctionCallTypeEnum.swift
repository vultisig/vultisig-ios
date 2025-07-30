//
//  FunctionCallTypeEnum.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import SwiftUI
import Foundation
import Combine

enum FunctionCallType: String, CaseIterable, Identifiable {
    case bond, unbond, bondMaya, unbondMaya, leave, custom, vote, stake, stakeTcy, unstake, unstakeTcy, addPool, removePool, cosmosIBC, merge, unmerge, theSwitch, yRuneTcy
    
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
        case .stakeTcy:
            return "Stake TCY"
        case .unstakeTcy:
            return "Unstake TCY"
        case .unstake:
            return "Unstake"
        case .cosmosIBC:
            return "IBC Transfer"
        case .merge:
            return "The Merge"
        case .unmerge:
            return "Unmerge RUJI"
        case .theSwitch:
            return "Switch"
        case .yRuneTcy:
            return "Exchange yRUNE/yTCY"
        }
    }
    
    static func getCases(for coin: Coin) -> [FunctionCallType] {
        switch coin.chain {
        case .thorChain:
            if coin.ticker.uppercased() == "TCY" {
                return [.bond, .unbond, .leave, .merge, .unmerge, .custom, .stakeTcy, .unstakeTcy, .yRuneTcy]
            }
            return [.bond, .unbond, .leave, .merge, .unmerge, .custom, .yRuneTcy]
        case .mayaChain:
            return [.bondMaya, .unbondMaya, .leave, .custom, .addPool, .removePool]
        case .dydx:
            return [.vote]
        case .ton:
            return [.stake, .unstake]
        case .gaiaChain:
            return [.cosmosIBC, .theSwitch]
        case .kujira:
            return [.cosmosIBC]
        case .osmosis:
            return [.cosmosIBC]
        case .noble:
            return [.cosmosIBC]
        case .akash:
            return [.cosmosIBC]
            
        default:
            return []
        }
    }
    
    static func getDefault(for coin: Coin) -> FunctionCallType {
        switch coin.chain {
        case .thorChain:
            return .bond
        case .mayaChain:
            return .bondMaya
        case .dydx:
            return .vote
        case .ton:
            return .stake
        case .gaiaChain:
            return .theSwitch
        case .kujira:
            return .cosmosIBC
        default:
            return .custom
        }
    }
}
