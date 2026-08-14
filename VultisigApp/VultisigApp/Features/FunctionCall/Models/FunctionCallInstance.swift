//
//  FunctionCallInstance.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import BigInt
import Foundation

enum FunctionCallInstance {

    /// The active sub-model, type-erased to the shared surface. Every
    /// accessor below forwards through here so the closed set is switched
    /// exactly once instead of once per accessor.
    @MainActor
    var model: any FunctionCallSubModel {
        switch self {
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
    /// preselected.
    ///
    /// Always nil now: every operation the Functions entry point offers has
    /// moved to `Features/FunctionTransaction/`, so there is no legacy form
    /// left for any chain to open on. Kept only so the legacy screen still
    /// compiles until it is deleted; no route reaches it, because every entry
    /// carries a preselected operation.
    @MainActor
    static func getDefault(for coin: Coin, vault: Vault) -> FunctionCallInstance? {
        nil
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
