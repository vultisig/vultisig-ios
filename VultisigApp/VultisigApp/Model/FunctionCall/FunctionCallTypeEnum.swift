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
    case
         rebond,
         bondMaya,
         unbondMaya,
         leave,
         custom,
         vote,
         stake,
         unstake,
         addPool,
         removePool,
         cosmosIBC,
         merge,
         unmerge,
         theSwitch,
         addThorLP,
         securedAsset,
         withdrawSecuredAsset
    
    var id: String { self.rawValue }
    
    func display(coin: Coin) -> String {
        switch self {
        case .rebond:
            return "Rebond"
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
            return "Merge"
        case .unmerge:
            return "Withdraw RUJI"
        case .theSwitch:
            return "Switch"
        case .addThorLP:
            return "Add THORChain LP"
        case .securedAsset:
            return "Secured Assets"
        case .withdrawSecuredAsset:
            return "Withdraw Secured Asset"
        }
    }
    
    static func getCases(for coin: Coin) -> [FunctionCallType] {
        switch coin.chain {
        case .thorChain:
            return [
                .rebond,
                .leave,
                .merge,
                .unmerge,
                .custom,
                .securedAsset,
                .withdrawSecuredAsset
            ]
            
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .ethereum, .avalanche, .bscChain, .base, .ripple:
            return [
                .addThorLP,
                .securedAsset
            ]
        case .mayaChain:
            return [.bondMaya,
                    .unbondMaya,
                    .leave,
                    .custom,
                    .addPool,
                    .removePool]
        case .dydx:
            return [.vote]
        case .ton:
            return [
                .stake,
                .unstake
            ]
        case .gaiaChain:
            return [
                .cosmosIBC,
                .theSwitch
            ]
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
            if coin.ticker.contains("TCY") {
                return .custom
            }
            return .rebond
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
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .ethereum, .avalanche, .bscChain, .base, .ripple:
            return .addThorLP
        default:
            return .custom
        }
    }
}
