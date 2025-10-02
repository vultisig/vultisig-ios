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
    case bond,
         rebond,
         unbond,
         bondMaya,
         unbondMaya,
         leave,
         custom,
         vote,
         stake,
         stakeTcy,
         unstake,
         unstakeTcy,
         addPool,
         removePool,
         cosmosIBC,
         merge,
         unmerge,
         theSwitch,
         mintYRune,
         mintYTCY,
         redeemRune,
         redeemTCY,
         addThorLP,
         removeThorLP,
         stakeRuji,
         unstakeRuji,
         withdrawRujiRewards
    
    var id: String { self.rawValue }
    
    func display(coin: Coin) -> String {
        switch self {
        case .bond:
            if coin.chain == .mayaChain {
                return "Add Bondprovider to WL"
            }
            return "Bond"
        case .rebond:
            return "Rebond"
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
            return "Merge"
        case .unmerge:
            return "Withdraw RUJI"
        case .theSwitch:
            return "Switch"
        case .mintYRune:
            return "Mint yRUNE"
        case .mintYTCY:
            return "Mint yTCY"
        case .redeemRune:
            return "Redeem RUNE"
        case .redeemTCY:
            return "Redeem TCY"
        case .addThorLP:
            return "Add THORChain LP"
        case .removeThorLP:
            return "Remove THORChain LP"
        case .stakeRuji:
            return "Stake RUJI"
        case .unstakeRuji:
            return "Unstake RUJI"
        case .withdrawRujiRewards:
            return "Withdraw RUJI Rewards"
        }
    }
    
    static func getCases(for coin: Coin) -> [FunctionCallType] {
        switch coin.chain {
        case .thorChain:
            return [
                FunctionCallType.bond,
                .rebond,
                .unbond,
                .leave,
                .merge,
                .unmerge,
                .custom,
                .addThorLP,
                .removeThorLP,
                .stakeRuji,
                .unstakeRuji,
                .withdrawRujiRewards,
                .mintYRune, .redeemRune, .mintYTCY, .redeemTCY, .stakeTcy, .unstakeTcy]
            
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .ethereum, .avalanche, .bscChain, .base, .ripple:
            return [.addThorLP]
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
            return [.stake,
                    .unstake]
        case .gaiaChain:
            return [.cosmosIBC,
                    .theSwitch]
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
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .ethereum, .avalanche, .bscChain, .base, .ripple:
            return .addThorLP
        default:
            return .custom
        }
    }
}
