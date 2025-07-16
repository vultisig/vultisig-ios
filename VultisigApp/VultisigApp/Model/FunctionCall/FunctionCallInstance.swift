//
//  FunctionCallInstance.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import Combine
import Foundation
import SwiftUI
import VultisigCommonData

enum FunctionCallInstance {
    case bond(FunctionCallBond)
    case unbond(FunctionCallUnbond)
    case bondMaya(FunctionCallBondMayaChain)
    case unbondMaya(FunctionCallUnbondMayaChain)
    case leave(FunctionCallLeave)
    case custom(FunctionCallCustom)
    case vote(FunctionCallVote)
    case stake(FunctionCallStake)
    case stakeTcy(FunctionCallStakeTCY)
    case unstakeTcy(FunctionCallUnstakeTCY)
    case unstake(FunctionCallUnstake)
    case addPool(FunctionCallAddLiquidityMaya)
    case removePool(FunctionCallRemoveLiquidityMaya)
    case cosmosIBC(FunctionCallCosmosIBC)
    case merge(FunctionCallCosmosMerge)
    case unmerge(FunctionCallCosmosUnmerge)
    case theSwitch(FunctionCallCosmosSwitch)
    case addThorLP(FunctionCallAddThorLP)
    case removeThorLP(FunctionCallRemoveThorLP)
    
    var view: AnyView {
        switch self {
        case .bond(let memo):
            return memo.getView()
        case .unbond(let memo):
            return memo.getView()
        case .bondMaya(let memo):
            return memo.getView()
        case .unbondMaya(let memo):
            return memo.getView()
        case .leave(let memo):
            return memo.getView()
        case .custom(let memo):
            return memo.getView()
        case .vote(let memo):
            return memo.getView()
        case .stake(let memo):
            return memo.getView()
        case .stakeTcy(let memo):
            return memo.getView()
        case .unstakeTcy(let memo):
            return memo.getView()
        case .unstake(let memo):
            return memo.getView()
        case .addPool(let memo):
            return memo.getView()
        case .removePool(let memo):
            return memo.getView()
        case .cosmosIBC(let memo):
            return memo.getView()
        case .merge(let memo):
            return memo.getView()
        case .unmerge(let memo):
            return memo.getView()
        case .theSwitch(let memo):
            return memo.getView()
        case .addThorLP(let memo):
            return memo.getView()
        case .removeThorLP(let memo):
            return memo.getView()
        }
    }
    
    var description: String {
        switch self {
        case .bond(let memo):
            return memo.description
        case .unbond(let memo):
            return memo.description
        case .bondMaya(let memo):
            return memo.description
        case .unbondMaya(let memo):
            return memo.description
        case .leave(let memo):
            return memo.description
        case .custom(let memo):
            return memo.description
        case .vote(let memo):
            return memo.description
        case .stake(let memo):
            return memo.description
        case .stakeTcy(let memo):
            return memo.description
        case .unstakeTcy(let memo):
            return memo.description
        case .unstake(let memo):
            return memo.description
        case .addPool(let memo):
            return memo.description
        case .removePool(let memo):
            return memo.description
        case .cosmosIBC(let memo):
            return memo.description
        case .merge(let memo):
            return memo.description
        case .unmerge(let memo):
            return memo.description
        case .theSwitch(let memo):
            return memo.description
        case .addThorLP(let memo):
            return memo.description
        case .removeThorLP(let memo):
            return memo.description
        }
    }
    
    var amount: Decimal {
        switch self {
        case .bond(let memo):
            return memo.amount
        case .unbond:
            return .zero
        case .bondMaya(let memo):
            return memo.amount
        case .unbondMaya:
            return 1 / pow(10, 8)
        case .leave:
            return .zero
        case .custom(let memo):
            return memo.amount
        case .vote:
            return .zero
        case .stake(let memo):
            return memo.amount
        case .stakeTcy(let memo):
            return memo.amount
        case .unstakeTcy(_):
            return .zero // The amount goes in the memo
        case .unstake(let memo):
            return memo.amount  // You must send 1 TON to unstake with a "w" memo
        case .addPool(let memo):
            return memo.amount
        case .removePool(_):
            return .zero
        case .cosmosIBC(let memo):
            return memo.amount
        case .merge(let memo):
            return memo.amount
        case .unmerge(let memo):
            return memo.amount  // Now amount contains the shares as Decimal
        case .theSwitch(let memo):
            return memo.amount
        case .addThorLP(let memo):
            return memo.amount
        case .removeThorLP:
            return .zero // Remove LP doesn't require sending amount
        }
    }
    
    var toAddress: String? {
        switch self {
        case .stake(let memo):
            return memo.nodeAddress
        case .unstake(let memo):
            return memo.nodeAddress
        case .cosmosIBC(let memo):
            return memo.destinationAddress
        case .merge(let memo):
            return memo.destinationAddress
        case .unmerge(let memo):
            return memo.destinationAddress
        case .theSwitch(let memo):
            return memo.destinationAddress
        default:
            return nil
        }
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        switch self {
        case .bond(let memo):
            return memo.toDictionary()
        case .unbond(let memo):
            return memo.toDictionary()
        case .bondMaya(let memo):
            return memo.toDictionary()
        case .unbondMaya(let memo):
            return memo.toDictionary()
        case .leave(let memo):
            return memo.toDictionary()
        case .custom(let memo):
            return memo.toDictionary()
        case .vote(let memo):
            return memo.toDictionary()
        case .stake(let memo):
            return memo.toDictionary()
        case .stakeTcy(let memo):
            return memo.toDictionary()
        case .unstakeTcy(let memo):
            return memo.toDictionary()
        case .unstake(let memo):
            return memo.toDictionary()
        case .addPool(let memo):
            return memo.toDictionary()
        case .removePool(let memo):
            return memo.toDictionary()
        case .cosmosIBC(let memo):
            return memo.toDictionary()
        case .merge(let memo):
            return memo.toDictionary()
        case .unmerge(let memo):
            return memo.toDictionary()
        case .theSwitch(let memo):
            return memo.toDictionary()
        case .addThorLP(let memo):
            return memo.toDictionary()
        case .removeThorLP(let memo):
            return memo.toDictionary()
        }
    }
    
    func getTransactionType() -> VSTransactionType {
        switch self {
        case .vote(_):
            return VSTransactionType.vote
        case .cosmosIBC(_):
            return VSTransactionType.ibcTransfer
        case .merge(_):
            return VSTransactionType.thorMerge
        case .unmerge(_):
            return VSTransactionType.thorUnmerge
        default:
            return .unspecified
        }
    }
    
    var isTheFormValid: Bool {
        switch self {
        case .bond(let memo):
            return memo.isTheFormValid
        case .unbond(let memo):
            return memo.isTheFormValid
        case .bondMaya(let memo):
            return memo.isTheFormValid
        case .unbondMaya(let memo):
            return memo.isTheFormValid
        case .leave(let memo):
            return memo.isTheFormValid
        case .custom(let memo):
            return memo.isTheFormValid
        case .vote(let memo):
            return memo.isTheFormValid
        case .stake(let memo):
            return memo.isTheFormValid
        case .stakeTcy(let memo):
            return memo.isTheFormValid
        case .unstakeTcy(let memo):
            return memo.isTheFormValid
        case .unstake(let memo):
            return memo.isTheFormValid
        case .addPool(let memo):
            return memo.isTheFormValid
        case .removePool(let memo):
            return memo.isTheFormValid
        case .cosmosIBC(let memo):
            return memo.isTheFormValid
        case .merge(let memo):
            return memo.isTheFormValid
        case .unmerge(let memo):
            return memo.isTheFormValid
        case .theSwitch(let memo):
            return memo.isTheFormValid
        case .addThorLP(let memo):
            return memo.isTheFormValid
        case .removeThorLP(let memo):
            return memo.isTheFormValid
        }
    }
    
    static func getDefault(for coin: Coin, tx: SendTransaction, functionCallViewModel: FunctionCallViewModel, vault: Vault) -> FunctionCallInstance {
        switch coin.chain {
        case .thorChain:
            return .bond(FunctionCallBond(tx: tx, functionCallViewModel: functionCallViewModel))
        case .mayaChain:
            return .bondMaya(FunctionCallBondMayaChain(assets: nil))
        case .dydx:
            return .vote(FunctionCallVote())
        case .ton:
            return .stake(FunctionCallStake())
        case .gaiaChain:
            return .theSwitch(FunctionCallCosmosSwitch(tx: tx, functionCallViewModel: functionCallViewModel, vault: vault))
        case .kujira:
            return .cosmosIBC(FunctionCallCosmosIBC(tx: tx, functionCallViewModel: functionCallViewModel, vault: vault))
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .ethereum, .avalanche, .bscChain, .base, .ripple:
            if coin.isNativeToken {
                return .addThorLP(FunctionCallAddThorLP(tx: tx, functionCallViewModel: functionCallViewModel, vault: vault))
            }
            return .custom(FunctionCallCustom())
        default:
            return .custom(FunctionCallCustom())
        }
    }
}
