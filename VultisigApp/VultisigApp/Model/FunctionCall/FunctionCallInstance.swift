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
    case rebond(FunctionCallReBond)
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
    case mintYRune(FunctionCallCosmosYVault)
    case mintYTCY(FunctionCallCosmosYVault)
    case redeemRune(FunctionCallCosmosYVault)
    case redeemTCY(FunctionCallCosmosYVault)
    case addThorLP(FunctionCallAddThorLP)
    case removeThorLP(FunctionCallRemoveThorLP)
    case stakeRuji(FunctionCallStakeRuji)
    case unstakeRuji(FunctionCallUnstakeRuji)
    case withdrawRujiRewards(FunctionCallWithdrawRujiRewards)
    
    var view: AnyView {
        switch self {
        case .bond(let memo):
            return memo.getView()
        case .rebond(let memo):
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
        case .mintYRune(let memo):
            return memo.getView()
        case .mintYTCY(let memo):
            return memo.getView()
        case .redeemRune(let memo):
            return memo.getView()
        case .redeemTCY(let memo):
            return memo.getView()
        case .addThorLP(let memo):
            return memo.getView()
        case .removeThorLP(let memo):
            return memo.getView()
        case .stakeRuji(let memo):
            return memo.getView()
        case .unstakeRuji(let memo):
            return memo.getView()
        case .withdrawRujiRewards(let memo):
            return memo.getView()
        }
    }
    
    var description: String {
        switch self {
        case .bond(let memo):
            return memo.description
        case .rebond(let memo):
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
        case .mintYRune(let memo):
            return memo.description
        case .mintYTCY(let memo):
            return memo.description
        case .redeemRune(let memo):
            return memo.description
        case .redeemTCY(let memo):
            return memo.description
        case .addThorLP(let memo):
            return memo.description
        case .removeThorLP(let memo):
            return memo.description
        case .stakeRuji(let memo):
            return memo.description
        case .unstakeRuji(let memo):
            return memo.description
        case .withdrawRujiRewards(let memo):
            return memo.description
        }
    }
    
    var amount: Decimal {
        switch self {
        case .bond(let memo):
            return memo.amount
        case .rebond(let memo):
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
        case .mintYRune(let memo):
            return memo.amount
        case .mintYTCY(let memo):
            return memo.amount
        case .redeemRune(let memo):
            return memo.amount
        case .redeemTCY(let memo):
            return memo.amount
        case .addThorLP(let memo):
            return memo.amount
        case .removeThorLP(let removeLP):
            return removeLP.dustAmount // Use the dust amount from the instance
        case .stakeRuji(let memo):
            return memo.amount
        case .unstakeRuji(_):
            return .zero  // The amount goes in the memo
        case .withdrawRujiRewards(let memo):
            return memo.amount
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
        case .mintYRune(let memo):
            return memo.destinationAddress
        case .mintYTCY(let memo):
            return memo.destinationAddress
        case .redeemRune(let memo):
            return memo.destinationAddress
        case .redeemTCY(let memo):
            return memo.destinationAddress
        case .addThorLP(let memo):
            // For addThorLP, return the inbound address that was set by fetchInboundAddress()
            // This is essential for Bitcoin and other chains to know where to send funds
            return memo.tx.toAddress.isEmpty ? nil : memo.tx.toAddress
        case .stakeRuji(let memo):
            return memo.destinationAddress
        case .unstakeRuji(let memo):
            return memo.destinationAddress
        case .withdrawRujiRewards(let memo):
            return memo.destinationAddress
        default:
            return nil
        }
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        switch self {
        case .bond(let memo):
            return memo.toDictionary()
        case .rebond(let memo):
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
        case .mintYRune(let memo):
            return memo.toDictionary()
        case .mintYTCY(let memo):
            return memo.toDictionary()
        case .redeemRune(let memo):
            return memo.toDictionary()
        case .redeemTCY(let memo):
            return memo.toDictionary()
        case .addThorLP(let memo):
            return memo.toDictionary()
        case .removeThorLP(let memo):
            return memo.toDictionary()
        case .stakeRuji(let memo):
            return memo.toDictionary()
        case .unstakeRuji(let memo):
            return memo.toDictionary()
        case .withdrawRujiRewards(let memo):
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
        case .mintYRune(_), .mintYTCY(_), .redeemRune(_), .redeemTCY(_):
            return VSTransactionType.genericContract
        case .stakeRuji, .unstakeRuji, .withdrawRujiRewards:
            return VSTransactionType.genericContract
        case .stakeTcy(let call):
            return call.isAutoCompound ? VSTransactionType.genericContract : .unspecified
        case .unstakeTcy(let call):
            return call.isAutoCompound ? VSTransactionType.genericContract : .unspecified
        default:
            return .unspecified
        }
    }
    
    var isTheFormValid: Bool {
        switch self {
        case .bond(let memo):
            return memo.isTheFormValid
        case .rebond(let memo):
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
        case .mintYRune(let memo):
            return memo.isTheFormValid
        case .mintYTCY(let memo):
            return memo.isTheFormValid
        case .redeemRune(let memo):
            return memo.isTheFormValid
        case .redeemTCY(let memo):
            return memo.isTheFormValid
        case .addThorLP(let memo):
            return memo.isTheFormValid
        case .removeThorLP(let memo):
            return memo.isTheFormValid
        case .stakeRuji(let memo):
            return memo.isTheFormValid
        case .unstakeRuji(let memo):
            return memo.isTheFormValid
        case .withdrawRujiRewards(let memo):
            return memo.isTheFormValid
        }
    }
    
    var customErrorMessage: String? {
        switch self {
        case .rebond(let memo):
            return memo.customErrorMessage
        case .addThorLP(let memo):
            return memo.customErrorMessage
        case .stakeTcy(let memo):
            return memo.customErrorMessage
        case .stakeRuji(let memo):
            return memo.customErrorMessage
        case .mintYRune(let memo):
            return memo.customErrorMessage
        case .mintYTCY(let memo):
            return memo.customErrorMessage
        case .redeemRune(let memo):
            return memo.customErrorMessage
        case .redeemTCY(let memo):
            return memo.customErrorMessage
        default:
            return nil
        }
    }
    
    static func getDefault(for coin: Coin, tx: SendTransaction, functionCallViewModel: FunctionCallViewModel, vault: Vault) -> FunctionCallInstance {
        switch coin.chain {
        case .thorChain:
            return .bond(FunctionCallBond(tx: tx, functionCallViewModel: functionCallViewModel, vault: vault))
        case .mayaChain:
            return .bondMaya(FunctionCallBondMayaChain(assets: nil))
        case .dydx:
            return .vote(FunctionCallVote())
        case .ton:
            return .stake(FunctionCallStake(tx: tx))
        case .gaiaChain:
            return .theSwitch(FunctionCallCosmosSwitch(tx: tx, functionCallViewModel: functionCallViewModel, vault: vault))
        case .kujira:
            return .cosmosIBC(FunctionCallCosmosIBC(tx: tx, functionCallViewModel: functionCallViewModel, vault: vault))
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .ethereum, .avalanche, .bscChain, .base, .ripple:
            return .addThorLP(FunctionCallAddThorLP(tx: tx, functionCallViewModel: functionCallViewModel, vault: vault))
        default:
            return .custom(FunctionCallCustom())
        }
    }
    
    var wasmContractPayload: WasmExecuteContractPayload? {
        switch self {
        case .stakeRuji(let call):
            return call.wasmContractPayload
        case .unstakeRuji(let call):
            return call.wasmContractPayload
        case .withdrawRujiRewards(let call):
            return call.wasmContractPayload
        case .stakeTcy(let call):
            return call.wasmContractPayload
        case .unstakeTcy(let call):
            return call.wasmContractPayload
        case .mintYRune(let call):
            return call.wasmContractPayload
        case .mintYTCY(let call):
            return call.wasmContractPayload
        case .redeemRune(let call):
            return call.wasmContractPayload
        case .redeemTCY(let call):
            return call.wasmContractPayload
        default:
            return nil
        }
    }
}
