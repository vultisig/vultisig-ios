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
    case rebond(FunctionCallReBond)
    case bondMaya(FunctionCallBondMayaChain)
    case unbondMaya(FunctionCallUnbondMayaChain)
    case leave(FunctionCallLeave)
    case custom(FunctionCallCustom)
    case vote(FunctionCallVote)
    case stake(FunctionCallStake)
    case unstake(FunctionCallUnstake)
    case cosmosIBC(FunctionCallCosmosIBC)
    case merge(FunctionCallCosmosMerge)
    case unmerge(FunctionCallCosmosUnmerge)
    case theSwitch(FunctionCallCosmosSwitch)
    case addThorLP(FunctionCallAddThorLP)
    case securedAsset(FunctionCallSecuredAsset)
    case withdrawSecuredAsset(FunctionCallWithdrawSecuredAsset)
    
    var view: AnyView {
        switch self {
        case .rebond(let memo):
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
        case .unstake(let memo):
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
        case .securedAsset(let memo):
            return memo.getView()
        case .withdrawSecuredAsset(let memo):
            return memo.getView()
        }
    }
    
    var description: String {
        switch self {
        case .rebond(let memo):
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
        case .unstake(let memo):
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
        case .securedAsset(let memo):
            return memo.description
        case .withdrawSecuredAsset(let memo):
            return memo.description
        }
    }
    
    var amount: Decimal {
        switch self {
        case .rebond:
            return 0  // REBOND must send 0 RUNE in the transaction
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
        case .unstake(let memo):
            return memo.amount  // You must send 1 TON to unstake with a "w" memo
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
        case .securedAsset(let memo):
            return memo.amount
        case .withdrawSecuredAsset(let memo):
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
        case .addThorLP(let memo):
            // For addThorLP, return the inbound address that was set by fetchInboundAddress()
            // This is essential for Bitcoin and other chains to know where to send funds
            return memo.tx.toAddress.isEmpty ? nil : memo.tx.toAddress
        case .securedAsset(let memo):
            // For secured assets (MINT), return the inbound address
            return memo.tx.toAddress.isEmpty ? nil : memo.tx.toAddress
        case .withdrawSecuredAsset:
            return nil // Withdraw is done via MsgDeposit on THORChain
        default:
            return nil
        }
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        switch self {
        case .rebond(let memo):
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
        case .unstake(let memo):
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
        case .securedAsset(let memo):
            return memo.toDictionary()
        case .withdrawSecuredAsset(let memo):
            return memo.toDictionary()
        }
    }
    
    func getTransactionType() -> VSTransactionType {
        switch self {
        case .vote:
            return VSTransactionType.vote
        case .cosmosIBC:
            return VSTransactionType.ibcTransfer
        case .merge:
            return VSTransactionType.thorMerge
        case .unmerge:
            return VSTransactionType.thorUnmerge
        default:
            return .unspecified
        }
    }
    
    var isTheFormValid: Bool {
        switch self {
        case .rebond(let memo):
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
        case .unstake(let memo):
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
        case .securedAsset(let memo):
            return memo.isTheFormValid
        case .withdrawSecuredAsset(let memo):
            return memo.isTheFormValid
        }
    }
    
    var customErrorMessage: String? {
        switch self {
        case .rebond(let memo):
            return memo.customErrorMessage
        case .addThorLP(let memo):
            return memo.customErrorMessage
        case .securedAsset(let memo):
            return memo.customErrorMessage
        case .withdrawSecuredAsset(let memo):
            return memo.customErrorMessage
        default:
            return nil
        }
    }
    
    static func getDefault(for coin: Coin, tx: SendTransaction, vault: Vault) -> FunctionCallInstance {
        switch coin.chain {
        case .thorChain:
            if coin.ticker.uppercased() == "TCY" {
                return .custom(FunctionCallCustom(tx: tx, vault: vault))
            }
            return .rebond(FunctionCallReBond(tx: tx, vault: vault))
        case .mayaChain:
            return .bondMaya(FunctionCallBondMayaChain(assets: nil))
        case .dydx:
            return .vote(FunctionCallVote())
        case .ton:
            return .stake(FunctionCallStake(tx: tx))
        case .gaiaChain:
            return .theSwitch(FunctionCallCosmosSwitch(tx: tx, vault: vault))
        case .kujira:
            return .cosmosIBC(FunctionCallCosmosIBC(tx: tx, vault: vault))
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .ethereum, .avalanche, .bscChain, .base, .ripple:
            return .addThorLP(FunctionCallAddThorLP(tx: tx, vault: vault))
        default:
            return .custom(FunctionCallCustom(tx: tx, vault: vault))
        }
    }
    
    var wasmContractPayload: WasmExecuteContractPayload? {
        switch self {
        case .securedAsset:
            return nil // Secured assets don't use WASM contracts
        case .withdrawSecuredAsset:
            return nil // Withdraw secured assets don't use WASM contracts
        default:
            return nil
        }
    }
}
