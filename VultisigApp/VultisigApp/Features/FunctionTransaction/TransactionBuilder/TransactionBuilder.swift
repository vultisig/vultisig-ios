//
//  TransactionBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 04/11/2025.
//

import Foundation
import VultisigCommonData

protocol TransactionBuilder {
    var coin: Coin { get }
    var amount: String { get }
    var sendMaxAmount: Bool { get }
    var memo: String { get }
    var memoFunctionDictionary: ThreadSafeDictionary<String, String> { get }
    var transactionType: VSTransactionType { get }
    var wasmContractPayload: WasmExecuteContractPayload? { get }
    var toAddress: String { get }
    /// Cosmos-SDK staking / distribution operation intent. Populated only by
    /// the per-flow Cosmos staking builders (delegate, undelegate, redelegate,
    /// withdrawRewards); every other builder uses the default `nil`.
    var cosmosStakingPayload: CosmosStakingPayload? { get }
    /// Solana native-staking operation intent. Populated only by the Solana
    /// staking builders (delegate today); every other builder uses the default
    /// `nil`.
    var solanaStakingPayload: SolanaStakingPayload? { get }
    /// The limit order this transaction cancels. Populated only by
    /// `CancelLimitOrderTransactionBuilder`; every other builder uses `nil`.
    ///
    /// Carried so the done screen can record that a cancel was broadcast for
    /// this specific order — the memo alone identifies the order only to
    /// THORChain, not to our own table.
    var limitCancelContext: LimitOrderCancelRequest? { get }
    /// What this transaction withdraws, when `amount` cannot say.
    ///
    /// A THORChain staking withdrawal is a memo-only `MsgDeposit`: its `amount`
    /// is the literal `"0"` and the instruction is a *fraction* of the staked
    /// position (`tcy-:<bps>`), so nothing downstream can recover the figure —
    /// which is how the verify screen came to announce "You're sending 0 TCY"
    /// over a withdrawal of a thousand of them.
    ///
    /// Already quantised to what the memo can express, so it is what the chain
    /// will pay out rather than the raw string that was typed. Populated only by
    /// the TCY unstake builder; every other builder uses the default `nil` and
    /// keeps its existing presentation.
    var withdrawDisplayAmount: Decimal? { get }
}

extension TransactionBuilder {
    /// Default — only Cosmos staking builders override this. Keeping the
    /// requirement defaulted means every existing `TransactionBuilder`
    /// conformer compiles unchanged.
    var cosmosStakingPayload: CosmosStakingPayload? { nil }

    /// Default — only Solana staking builders override this.
    var solanaStakingPayload: SolanaStakingPayload? { nil }

    /// Default — only the limit-order cancel builder overrides this.
    var limitCancelContext: LimitOrderCancelRequest? { nil }

    /// Default — only the TCY unstake builder overrides this.
    var withdrawDisplayAmount: Decimal? { nil }

    /// Builds the immutable `SendTransaction` struct directly, with `gas` /
    /// `fee` and runtime-only fields left at the construction-time zero state.
    ///
    /// ⚠️ **Unpriced.** Nothing downstream of `FunctionTransactionRoute.verify`
    /// re-resolves the two fee figures for display — `FunctionTransactionVerifyScreen`
    /// renders whatever the hand-off carried — so a transaction navigated
    /// straight from here discloses a zero fee. Use
    /// `buildPricedSendTransaction(vault:)` at any seam that hands the result to
    /// Verify; this stays for the flows that stamp their own fee (the Cosmos
    /// staking constant, a THORChain deposit's fixed gas) and for tests.
    func buildSendTransaction(vault: Vault) -> SendTransaction {
        SendTransaction(
            coin: coin,
            vault: vault,
            fromAddress: coin.address,
            toAddress: toAddress,
            toAddressLabel: nil,
            amount: amount,
            amountInFiat: "",
            memo: memo,
            gas: .zero,
            fee: .zero,
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: sendMaxAmount,
            isStakingOperation: cosmosStakingPayload != nil || solanaStakingPayload != nil,
            transactionType: transactionType,
            memoFunctionDictionary: memoFunctionDictionary.allItems(),
            wasmContractPayload: wasmContractPayload,
            feeCoin: SendTransaction.resolveFeeCoin(coin: coin, vault: vault),
            cosmosStakingPayload: cosmosStakingPayload,
            solanaStakingPayload: solanaStakingPayload,
            limitCancelContext: limitCancelContext,
            withdrawDisplayAmount: withdrawDisplayAmount
        )
    }

    /// The transaction Verify is handed: built, then priced.
    ///
    /// One step for every builder, present and future, so a DeFi operation
    /// migrated onto this pipeline discloses a real fee the day it lands rather
    /// than inheriting a `chainSpecific.gas` copy that reads zero on EVM, UTXO
    /// and Cardano. See `FunctionTransactionFeePricer` for why the two figures must
    /// travel together.
    @MainActor
    func buildPricedSendTransaction(
        vault: Vault,
        pricer: FunctionTransactionFeePricer
    ) async -> SendTransaction {
        await pricer.priced(buildSendTransaction(vault: vault))
    }

    /// `buildPricedSendTransaction(vault:pricer:)` against the live interactor.
    @MainActor
    func buildPricedSendTransaction(vault: Vault) async -> SendTransaction {
        await buildPricedSendTransaction(vault: vault, pricer: FunctionTransactionFeePricer())
    }
}
