//
//  FunctionCallSubModel.swift
//  VultisigApp
//
//  Shared surface for the 13 FunctionCall sub-models. Reintroduced so
//  `FunctionCallInstance` can dispatch through a single `model` accessor
//  instead of re-`switch`ing the same closed set in every accessor.
//  Each sub-model already implements the memo / amount / validity /
//  transaction-building surface directly; this protocol only names it and
//  supplies nil defaults for the two accessors most sub-models opt out of
//  (`resolvedToAddress`, `submitErrorMessage`).
//

import BigInt
import Foundation

@MainActor
protocol FunctionCallSubModel {
    /// On-chain memo preview for this function call.
    var description: String { get }

    /// Asset amount the transaction carries (memo-only calls emit zero).
    var amount: Decimal { get }

    /// Destination address surfaced through `FunctionCallInstance.toAddress`.
    /// Defaults to `nil`; only sub-models that route funds to an explicit
    /// on-chain destination override it.
    var resolvedToAddress: String? { get }

    /// Error surfaced through `FunctionCallInstance.customErrorMessage`.
    /// Defaults to `nil`; only the sub-models whose error the instance
    /// forwarded before this collapse override it. Kept distinct from the
    /// sub-models' own `customErrorMessage` slot so a sub-model that tracks
    /// an internal error (e.g. unmerge) does not leak it through the
    /// instance accessor, preserving the pre-refactor behaviour.
    var submitErrorMessage: String? { get }

    /// Submit-time validity gate, threaded the active coin.
    func isFormValid(for coin: Coin) -> Bool

    /// Build the immutable `SendTransaction` fed into signing.
    func toSendTransaction(coin: Coin, vault: Vault, gas: BigInt) -> SendTransaction
}

@MainActor
extension FunctionCallSubModel {
    var resolvedToAddress: String? { nil }
    var submitErrorMessage: String? { nil }
}

// MARK: - Conformances
//
// Each sub-model already declares `description`, `amount` and
// `toSendTransaction(coin:vault:gas:)` in its primary body; the conformance
// only adds the shims the protocol can't infer:
//   • `isFormValid(for:)` bridges to the sub-model's `isTheFormValid` where
//     the sub-model has no coin-threaded gate.
//   • `resolvedToAddress` / `submitErrorMessage` reproduce the exact per-case
//     mapping the old `FunctionCallInstance.toAddress` /
//     `.customErrorMessage` switches encoded.

extension FunctionCallReBond: FunctionCallSubModel {
    func isFormValid(for _: Coin) -> Bool { isTheFormValid }
    var submitErrorMessage: String? { customErrorMessage }
}

extension FunctionCallBondMayaChain: FunctionCallSubModel {
    func isFormValid(for _: Coin) -> Bool { isTheFormValid }
}

extension FunctionCallUnbondMayaChain: FunctionCallSubModel {
    func isFormValid(for _: Coin) -> Bool { isTheFormValid }
}

extension FunctionCallLeave: FunctionCallSubModel {
    func isFormValid(for _: Coin) -> Bool { isTheFormValid }
}

extension FunctionCallCustom: FunctionCallSubModel {}

extension FunctionCallVote: FunctionCallSubModel {
    func isFormValid(for _: Coin) -> Bool { isTheFormValid }
}

extension FunctionCallCosmosIBC: FunctionCallSubModel {
    var resolvedToAddress: String? { destinationAddress }
}

extension FunctionCallCosmosMerge: FunctionCallSubModel {
    var resolvedToAddress: String? { destinationAddress }
}

extension FunctionCallCosmosUnmerge: FunctionCallSubModel {
    func isFormValid(for _: Coin) -> Bool { isTheFormValid }
    var resolvedToAddress: String? { destinationAddress }
}

extension FunctionCallCosmosSwitch: FunctionCallSubModel {
    var resolvedToAddress: String? { destinationAddress }
}

extension FunctionCallAddThorLP: FunctionCallSubModel {
    func isFormValid(for _: Coin) -> Bool { isTheFormValid }
    var resolvedToAddress: String? { toAddress.isEmpty ? nil : toAddress }
    var submitErrorMessage: String? { customErrorMessage }
}

extension FunctionCallSecuredAsset: FunctionCallSubModel {
    func isFormValid(for _: Coin) -> Bool { isTheFormValid }
    var resolvedToAddress: String? { toAddress.isEmpty ? nil : toAddress }
    var submitErrorMessage: String? { customErrorMessage }
}

extension FunctionCallWithdrawSecuredAsset: FunctionCallSubModel {
    func isFormValid(for _: Coin) -> Bool { isTheFormValid }
    var submitErrorMessage: String? { customErrorMessage }
}
