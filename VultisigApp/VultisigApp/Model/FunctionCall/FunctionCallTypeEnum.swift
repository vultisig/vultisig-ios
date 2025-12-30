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
            return NSLocalizedString("Rebond", comment: "")
        case .bondMaya:
            return NSLocalizedString("Bond", comment: "")
        case .unbondMaya:
            return NSLocalizedString("Unbond", comment: "")
        case .leave:
            return NSLocalizedString("Leave", comment: "")
        case .custom:
            return NSLocalizedString("Custom", comment: "")
        case .vote:
            return NSLocalizedString("Vote", comment: "")
        case .stake:
            return NSLocalizedString("Stake", comment: "")
        case .unstake:
            return NSLocalizedString("Unstake", comment: "")
        case .cosmosIBC:
            return NSLocalizedString("IBC Transfer", comment: "")
        case .merge:
            return NSLocalizedString("Merge", comment: "")
        case .unmerge:
            return NSLocalizedString("Withdraw RUJI", comment: "")
        case .theSwitch:
            return NSLocalizedString("Switch", comment: "")
        case .addThorLP:
            return NSLocalizedString("Add THORChain LP", comment: "")
        case .securedAsset:
            return NSLocalizedString("Secured Assets", comment: "")
        case .withdrawSecuredAsset:
            return NSLocalizedString("Withdraw Secured Asset", comment: "")
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
                    .custom]
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
