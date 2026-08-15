//
//  IBCTransferTransactionBuilder.swift
//  VultisigApp
//
//  Cosmos IBC transfer — moving a native asset to another IBC-connected chain
//  over a known channel.
//
//  Every value the transfer needs is a field here. The one place they become a
//  string is `memo`, and only because the source channel has nowhere else to
//  travel: `CosmosSpecific` carries no channel, and each co-signing device
//  rebuilds its payload from that proto and signs what it derives, so a value
//  the initiator keeps in Swift memory is a value the peer cannot see.
//  `CosmosIBCTransferMemo` owns that encoding on both ends — the signer decodes
//  through the same type rather than splitting the string itself.
//

import Foundation
import VultisigCommonData

struct IBCTransferTransactionBuilder: TransactionBuilder {
    /// The asset being transferred, on the source chain.
    let coin: Coin
    /// Where it lands. Its `sourceChannel` is the value the signing path
    /// recovers from the memo, and the only one here that changes what is
    /// signed — carried with the destination rather than looked up again, so
    /// the route the user picked is the route that gets signed.
    let destination: IBCDestination
    /// The receiving address on `destination.chain`.
    let destinationAddress: String
    /// The user's own memo, forwarded to the destination. Empty when absent.
    let userMemo: String
    /// Human-decimal amount, already read out of the field by
    /// `IBCTransferAmount` and re-rendered at the coin's scale — the same
    /// `formatToDecimal(digits:)` the legacy sub-model applied, so
    /// `SendTransaction.amountInRaw` resolves to the identical base-unit value.
    let amount: String

    let sendMaxAmount: Bool = false

    var memo: String {
        CosmosIBCTransferMemo(
            destinationChainName: destination.chain.name,
            sourceChannel: destination.sourceChannel,
            destinationAddress: destinationAddress,
            userMemo: userMemo
        ).packed
    }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("destinationChain", destination.chain.name)
        dict.set("destinationChannel", destination.sourceChannel)
        dict.set("destinationAddress", destinationAddress)
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .ibcTransfer }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    /// The receiving address. The transfer message reads its receiver from
    /// here, not from the memo's copy.
    var toAddress: String { destinationAddress }
}
