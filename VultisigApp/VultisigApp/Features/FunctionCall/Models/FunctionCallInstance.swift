//
//  FunctionCallInstance.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import BigInt
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

    @MainActor
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

    @MainActor
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

    @MainActor
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
            return memo.toAddress.isEmpty ? nil : memo.toAddress
        case .securedAsset(let memo):
            // For secured assets (MINT), return the inbound address
            return memo.toAddress.isEmpty ? nil : memo.toAddress
        case .withdrawSecuredAsset:
            return nil // Withdraw is done via MsgDeposit on THORChain
        default:
            return nil
        }
    }

    @MainActor
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

    @MainActor
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

    /// Submit-time validity gate. Threads the active coin to every
    /// sub-model so the amount-against-balance check is part of the
    /// same predicate the Continue button reads — no no-arg path can
    /// drift past `amount <= balance` again. Sub-models that don't
    /// need the coin keep their existing `isTheFormValid` body and the
    /// parameter just falls through.
    @MainActor
    func isFormValid(for coin: Coin) -> Bool {
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
            return memo.isFormValid(for: coin)
        case .unstake(let memo):
            return memo.isFormValid(for: coin)
        case .cosmosIBC(let memo):
            return memo.isFormValid(for: coin)
        case .merge(let memo):
            return memo.isFormValid(for: coin)
        case .unmerge(let memo):
            return memo.isTheFormValid
        case .theSwitch(let memo):
            return memo.isFormValid(for: coin)
        case .addThorLP(let memo):
            return memo.isTheFormValid
        case .securedAsset(let memo):
            return memo.isTheFormValid
        case .withdrawSecuredAsset(let memo):
            return memo.isTheFormValid
        }
    }

    @MainActor
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

    @MainActor
    static func getDefault(for coin: Coin, vault: Vault) -> FunctionCallInstance {
        switch coin.chain {
        case .thorChain:
            if coin.ticker.uppercased() == "TCY" {
                return .custom(FunctionCallCustom(coin: coin, vault: vault))
            }
            return .rebond(FunctionCallReBond())
        case .mayaChain:
            return .bondMaya(FunctionCallBondMayaChain(assets: nil))
        case .dydx:
            return .vote(FunctionCallVote())
        case .ton:
            return .stake(FunctionCallStake(initialAmount: coin.balanceDecimal))
        case .gaiaChain:
            return .theSwitch(FunctionCallCosmosSwitch(coin: coin, vault: vault))
        case .kujira:
            return .cosmosIBC(FunctionCallCosmosIBC(coin: coin, vault: vault))
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .ethereum, .avalanche, .bscChain, .base, .ripple:
            return .addThorLP(FunctionCallAddThorLP(coin: coin, vault: vault))
        default:
            return .custom(FunctionCallCustom(coin: coin, vault: vault))
        }
    }

    @MainActor
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

    /// Build the immutable `SendTransaction` for the active sub-model.
    /// After PR3 (C-2e), every case dispatches through its typed
    /// `toSendTransaction(coin:vault:gas:isFastVault:)` method.
    @MainActor
    func toSendTransaction(
        coin: Coin,
        vault: Vault,
        gas: BigInt,
        isFastVault: Bool
    ) -> SendTransaction {
        switch self {
        case .rebond(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas, isFastVault: isFastVault)
        case .bondMaya(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas, isFastVault: isFastVault)
        case .unbondMaya(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas, isFastVault: isFastVault)
        case .leave(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas, isFastVault: isFastVault)
        case .custom(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas, isFastVault: isFastVault)
        case .vote(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas, isFastVault: isFastVault)
        case .stake(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas, isFastVault: isFastVault)
        case .unstake(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas, isFastVault: isFastVault)
        case .cosmosIBC(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas, isFastVault: isFastVault)
        case .merge(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas, isFastVault: isFastVault)
        case .unmerge(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas, isFastVault: isFastVault)
        case .theSwitch(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas, isFastVault: isFastVault)
        case .addThorLP(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas, isFastVault: isFastVault)
        case .securedAsset(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas, isFastVault: isFastVault)
        case .withdrawSecuredAsset(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas, isFastVault: isFastVault)
        }
    }
}
