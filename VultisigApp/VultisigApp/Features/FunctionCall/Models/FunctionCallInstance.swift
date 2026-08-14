//
//  FunctionCallInstance.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import BigInt
import Foundation

enum FunctionCallInstance {
    case custom(FunctionCallCustom)
    case vote(FunctionCallVote)
    case cosmosIBC(FunctionCallCosmosIBC)
    case unmerge(FunctionCallCosmosUnmerge)
    case theSwitch(FunctionCallCosmosSwitch)
    case withdrawSecuredAsset(FunctionCallWithdrawSecuredAsset)

    /// The active sub-model, type-erased to the shared surface. Every
    /// accessor below forwards through here so the closed set is switched
    /// exactly once instead of once per accessor.
    @MainActor
    var model: any FunctionCallSubModel {
        switch self {
        case .custom(let memo): return memo
        case .vote(let memo): return memo
        case .cosmosIBC(let memo): return memo
        case .unmerge(let memo): return memo
        case .theSwitch(let memo): return memo
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
    /// Optional because the answer genuinely can be "none": every chain whose
    /// whole case list has moved to `Features/FunctionTransaction/` — the nine
    /// Add-LP L1s, MayaChain, dYdX — has no legacy form to open on at all.
    /// Returning some other sub-model to keep the signature total would open a
    /// form for an operation the chain does not offer, which is the defect
    /// class the action list was built to end.
    ///
    /// Derived from `FunctionCallType.getDefault` rather than re-deriving the
    /// chain mapping. The two used to answer the same question with different
    /// relations — one matched any THORChain ticker *containing* "TCY", the
    /// other matched it exactly — so a holder of a TCY wrapper was routed to
    /// one operation and handed another's form.
    ///
    /// No caller reaches this path: every route into the legacy screen carries
    /// a preselected operation. It is kept in step with the type factory so the
    /// two cannot silently diverge before the legacy shell is deleted.
    @MainActor
    static func getDefault(for coin: Coin, vault: Vault) -> FunctionCallInstance? {
        let type = FunctionCallType.getDefault(for: coin)
        guard type.migratedTransactionType(coin: coin, nodeAddress: nil) == nil else { return nil }

        switch type {
        case .custom:
            return .custom(FunctionCallCustom(coin: coin, vault: vault))
        case .vote:
            return .vote(FunctionCallVote())
        case .cosmosIBC:
            return .cosmosIBC(FunctionCallCosmosIBC(coin: coin, vault: vault))
        case .theSwitch:
            return .theSwitch(FunctionCallCosmosSwitch(coin: coin, vault: vault))
        default:
            // No chain opens on these, and an operation that is never a default
            // has no business being built by a default factory.
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
