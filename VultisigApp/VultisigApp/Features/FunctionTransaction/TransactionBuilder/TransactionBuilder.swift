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
}

extension TransactionBuilder {
    /// Default — only Cosmos staking builders override this. Keeping the
    /// requirement defaulted means every existing `TransactionBuilder`
    /// conformer compiles unchanged.
    var cosmosStakingPayload: CosmosStakingPayload? { nil }

    // Builds the legacy mutable form-state class. Used by call sites that
    // continue mutating fields downstream (e.g. `tx.gas`, `tx.fastVaultPassword`).
    // Once the FunctionCall flow migrates to a per-flow form VM this method
    // goes away in favor of `buildSendTransaction(vault:)`.
    func buildTransaction() -> FunctionCallForm {
        let sendTx = FunctionCallForm()
        sendTx.fromAddress = coin.address
        sendTx.coin = coin
        sendTx.amount = amount
        sendTx.memo = memo
        sendTx.memoFunctionDictionary = memoFunctionDictionary
        sendTx.transactionType = transactionType
        sendTx.wasmContractPayload = wasmContractPayload
        sendTx.toAddress = toAddress

        return sendTx
    }

    // Builds the immutable `SendTransaction` struct directly. Preferred for
    // new call sites — `gas` / `fee` and runtime-only fields default to the
    // construction-time zero state and are filled in downstream by
    // `SendCryptoVerifyViewModel` (via the interactor).
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
            isStakingOperation: cosmosStakingPayload != nil,
            transactionType: transactionType,
            memoFunctionDictionary: memoFunctionDictionary.allItems(),
            wasmContractPayload: wasmContractPayload,
            feeCoin: SendTransaction.resolveFeeCoin(coin: coin, vault: vault),
            cosmosStakingPayload: cosmosStakingPayload
        )
    }
}
