//
//  FunctionCallInstance.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import BigInt
import Foundation

enum FunctionCallInstance {
    case rebond(FunctionCallReBond)
    case custom(FunctionCallCustom)
    case vote(FunctionCallVote)
    case cosmosIBC(FunctionCallCosmosIBC)
    case merge(FunctionCallCosmosMerge)
    case unmerge(FunctionCallCosmosUnmerge)
    case theSwitch(FunctionCallCosmosSwitch)
    case securedAsset(FunctionCallSecuredAsset)
    case withdrawSecuredAsset(FunctionCallWithdrawSecuredAsset)

    /// The active sub-model, type-erased to the shared surface. Every
    /// accessor below forwards through here so the closed set is switched
    /// exactly once instead of once per accessor.
    @MainActor
    var model: any FunctionCallSubModel {
        switch self {
        case .rebond(let memo): return memo
        case .custom(let memo): return memo
        case .vote(let memo): return memo
        case .cosmosIBC(let memo): return memo
        case .merge(let memo): return memo
        case .unmerge(let memo): return memo
        case .theSwitch(let memo): return memo
        case .securedAsset(let memo): return memo
        case .withdrawSecuredAsset(let memo): return memo
        }
    }

    @MainActor
    var description: String {
        model.description
    }

    @MainActor
    var amount: Decimal {
        model.amount
    }

    @MainActor
    var toAddress: String? {
        model.resolvedToAddress
    }

    /// Submit-time validity gate. Threads the active coin to every
    /// sub-model so the amount-against-balance check is part of the
    /// same predicate the Continue button reads — no no-arg path can
    /// drift past `amount <= balance` again. Sub-models that don't
    /// need the coin bridge to their existing `isTheFormValid` body and
    /// the parameter just falls through.
    @MainActor
    func isFormValid(for coin: Coin) -> Bool {
        model.isFormValid(for: coin)
    }

    @MainActor
    var customErrorMessage: String? {
        model.submitErrorMessage
    }

    @MainActor
    static func getDefault(for coin: Coin, vault: Vault) -> FunctionCallInstance {
        switch coin.chain {
        case .thorChain:
            if coin.ticker.uppercased() == "TCY" {
                return .custom(FunctionCallCustom(coin: coin, vault: vault))
            }
            return .rebond(FunctionCallReBond())
        // Keep in step with `FunctionCallType.getDefault(for:)` — the screen
        // renders this instance under that selection, so the two disagreeing
        // shows one function's name over another function's form. MayaChain
        // has no arm: its LEAVE now has its own screen, so the raw-memo
        // fallthrough is the only Maya operation left with a legacy form.
        case .dydx:
            return .vote(FunctionCallVote())
        case .gaiaChain:
            return .theSwitch(FunctionCallCosmosSwitch(coin: coin, vault: vault))
        case .kujira:
            return .cosmosIBC(FunctionCallCosmosIBC(coin: coin, vault: vault))
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .ethereum, .avalanche, .bscChain, .base, .ripple:
            return .securedAsset(FunctionCallSecuredAsset(coin: coin, vault: vault))
        default:
            return .custom(FunctionCallCustom(coin: coin, vault: vault))
        }
    }

    /// Build the immutable `SendTransaction` for the active sub-model.
    /// Every case dispatches through its typed
    /// `toSendTransaction(coin:vault:gas:)` method.
    @MainActor
    func toSendTransaction(
        coin: Coin,
        vault: Vault,
        gas: BigInt
    ) -> SendTransaction {
        model.toSendTransaction(coin: coin, vault: vault, gas: gas)
    }
}
