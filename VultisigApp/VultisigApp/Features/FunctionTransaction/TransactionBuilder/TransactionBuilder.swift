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
    /// What this transaction *is*, when "a send" is the wrong word for it.
    ///
    /// Deliberately separate from `withdrawDisplayAmount`: that field answers
    /// "what figure", this one answers "what verb", and most builders need only
    /// the second. Optional and defaulted, so a builder opts in — which also
    /// means a NEW builder silently keeps the generic send header until someone
    /// names its kind. `FunctionTransactionKindTests` pins the mapping for the
    /// builders that exist; nothing can pin the ones that do not yet.
    var functionKind: FunctionTransactionKind? { get }
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

    /// Default — only the builders whose amount cannot state the operation's
    /// figure override this.
    var withdrawDisplayAmount: Decimal? { nil }

    /// Default — a builder that has not named its kind keeps the generic send
    /// header it has today.
    var functionKind: FunctionTransactionKind? { nil }

    /// Builds the immutable `SendTransaction` struct directly. `gas` /
    /// `fee` and runtime-only fields default to the construction-time
    /// zero state and are filled in downstream by `SendCryptoVerifyViewModel`
    /// (via the interactor).
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
            withdrawDisplayAmount: withdrawDisplayAmount,
            functionKind: functionKind
        )
    }
}
