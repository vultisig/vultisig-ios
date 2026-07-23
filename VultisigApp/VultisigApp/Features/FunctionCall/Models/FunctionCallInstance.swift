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

    /// Submit-time validity gate. Threads the active coin to every
    /// sub-model so the amount-against-balance check is part of the
    /// same predicate the Continue button reads — no no-arg path can
    /// drift past `amount <= balance` again. Sub-models that don't
    /// need the coin keep their existing `isTheFormValid` body and the
    /// parameter just falls through.
    @MainActor
    func isFormValid(for coin: Coin) -> Bool {
        switch self {
        // No coin-balance guard: REBOND burns zero RUNE — the optional
        // rebond amount is memo-only, never an on-chain transfer.
        case .rebond(let memo):
            return memo.isTheFormValid
        // No user-editable amount field — BOND sends a fixed amount.
        case .bondMaya(let memo):
            return memo.isTheFormValid
        // No user-editable amount field — UNBOND sends a fixed dust amount.
        case .unbondMaya(let memo):
            return memo.isTheFormValid
        // No amount: LEAVE burns zero RUNE, unbonds via the memo alone.
        case .leave(let memo):
            return memo.isTheFormValid
        case .custom(let memo):
            return memo.isFormValid(for: coin)
        // No amount: vote transactions carry zero value.
        case .vote(let memo):
            return memo.isTheFormValid
        case .cosmosIBC(let memo):
            return memo.isFormValid(for: coin)
        case .merge(let memo):
            return memo.isFormValid(for: coin)
        // Amount is a share quantity validated against the merged-position
        // balance (`availableBalance`), not the coin balance.
        case .unmerge(let memo):
            return memo.isTheFormValid
        case .theSwitch(let memo):
            return memo.isFormValid(for: coin)
        // Balance is checked internally against the sub-model's owned coin
        // (mutated by the pool dropdown), not the passed-in coin.
        case .addThorLP(let memo):
            return memo.isTheFormValid
        // Balance is checked internally against the sub-model's owned coin.
        case .securedAsset(let memo):
            return memo.isTheFormValid
        // Amount is validated against the selected secured-asset balance,
        // not the coin balance.
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
    /// `toSendTransaction(coin:vault:gas:)` method.
    @MainActor
    func toSendTransaction(
        coin: Coin,
        vault: Vault,
        gas: BigInt
    ) -> SendTransaction {
        switch self {
        case .rebond(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas)
        case .bondMaya(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas)
        case .unbondMaya(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas)
        case .leave(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas)
        case .custom(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas)
        case .vote(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas)
        case .cosmosIBC(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas)
        case .merge(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas)
        case .unmerge(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas)
        case .theSwitch(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas)
        case .addThorLP(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas)
        case .securedAsset(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas)
        case .withdrawSecuredAsset(let memo):
            return memo.toSendTransaction(coin: coin, vault: vault, gas: gas)
        }
    }
}
