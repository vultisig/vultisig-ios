//
//  TransactionBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 04/11/2025.
//

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
            limitCancelContext: limitCancelContext
        )
    }
}
