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
}

extension TransactionBuilder {
    // Builds the legacy mutable form-state class. Used by call sites that
    // continue mutating fields downstream (e.g. `tx.gas`, `tx.fastVaultPassword`).
    // Once the FunctionCall flow migrates to a per-flow form VM this method
    // goes away in favor of `buildSendTransaction(vault:)`.
    func buildTransaction() -> LegacySendTransaction {
        let sendTx = LegacySendTransaction()
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
            isFastVault: false,
            isStakingOperation: false,
            transactionType: transactionType,
            memoFunctionDictionary: memoFunctionDictionary.allItems(),
            wasmContractPayload: wasmContractPayload,
            feeCoin: SendTransaction.resolveFeeCoin(coin: coin, vault: vault)
        )
    }
}
