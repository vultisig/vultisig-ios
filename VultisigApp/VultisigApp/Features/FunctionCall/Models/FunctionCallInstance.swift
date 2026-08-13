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
    case bondMaya(FunctionCallBondMayaChain)
    case unbondMaya(FunctionCallUnbondMayaChain)
    case vote(FunctionCallVote)
    case cosmosIBC(FunctionCallCosmosIBC)
    case merge(FunctionCallCosmosMerge)
    case unmerge(FunctionCallCosmosUnmerge)
    case theSwitch(FunctionCallCosmosSwitch)
    case addThorLP(FunctionCallAddThorLP)
    case securedAsset(FunctionCallSecuredAsset)
    case withdrawSecuredAsset(FunctionCallWithdrawSecuredAsset)

    /// The active sub-model, type-erased to the shared surface. Every
    /// accessor below forwards through here so the closed set is switched
    /// exactly once instead of once per accessor.
    @MainActor
    var model: any FunctionCallSubModel {
        switch self {
        case .rebond(let memo): return memo
        case .bondMaya(let memo): return memo
        case .unbondMaya(let memo): return memo
        case .vote(let memo): return memo
        case .cosmosIBC(let memo): return memo
        case .merge(let memo): return memo
        case .unmerge(let memo): return memo
        case .theSwitch(let memo): return memo
        case .addThorLP(let memo): return memo
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

    /// The sub-model the legacy screen opens on when no operation was
    /// preselected, or `nil` when that chain's default has been migrated and
    /// has no legacy form left to build.
    ///
    /// Optional because the answer genuinely can be "none": `FunctionCallType
    /// .getDefault` falls back to the raw-memo operation for every chain
    /// without an arm of its own, and that operation now lives on
    /// `FunctionTransactionScreen`. Returning some other sub-model to keep the
    /// signature total would open a form for an operation the chain does not
    /// offer — the defect class the action list was built to end.
    ///
    /// No caller reaches this path: every route into the legacy screen carries
    /// a preselected operation. It is kept in step with `FunctionCallType
    /// .getDefault` so the two cannot silently diverge before the legacy shell
    /// is deleted.
    @MainActor
    static func getDefault(for coin: Coin, vault: Vault) -> FunctionCallInstance? {
        let type = FunctionCallType.getDefault(for: coin)
        // Derived from the type factory rather than re-deriving the chain
        // mapping. The two used to answer the same question with different
        // relations — one matched any THORChain ticker *containing* "TCY",
        // the other matched it exactly — so a holder of a TCY wrapper was sent
        // to one operation and handed another's form.
        guard type.migratedTransactionType(coin: coin, nodeAddress: nil) == nil else { return nil }

        switch type {
        case .rebond:
            return .rebond(FunctionCallReBond())
        case .bondMaya:
            return .bondMaya(FunctionCallBondMayaChain(assets: nil))
        case .vote:
            return .vote(FunctionCallVote())
        case .theSwitch:
            return .theSwitch(FunctionCallCosmosSwitch(coin: coin, vault: vault))
        case .cosmosIBC:
            return .cosmosIBC(FunctionCallCosmosIBC(coin: coin, vault: vault))
        case .addThorLP:
            return .addThorLP(FunctionCallAddThorLP(coin: coin, vault: vault))
        default:
            return nil
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
