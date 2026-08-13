//
//  SwitchTransactionBuilder.swift
//  VultisigApp
//
//  Cosmos Hub → THORChain SWITCH. A plain transfer of the source chain's
//  native asset to THORChain's inbound vault for that chain, carrying
//  `SWITCH:<thorAddress>` so the protocol credits the switched balance to a
//  THORChain address.
//
//  Two values here are fund-critical and neither has a safe default:
//  `inboundAddress` is the vault THORChain is currently observing — it churns,
//  and a retired one strands the transfer — and `switchAmount` is a real
//  transfer, unlike the memo-only node operations whose amount is pinned to
//  zero. Both are non-optional so a form that could not resolve them cannot
//  reach a builder at all.
//

import Foundation
import VultisigCommonData

struct SwitchTransactionBuilder: TransactionBuilder {
    /// The source chain's native asset. THORChain's inbound vault credits only
    /// that asset, so it is what the form pins rather than whatever coin the
    /// user happened to be looking at.
    let coin: Coin
    /// The THORChain address the switched balance is credited to — the memo's
    /// only argument.
    let thorchainAddress: String
    /// THORChain's live inbound vault for `coin.chain`, resolved when this
    /// builder is constructed rather than when the form opened.
    let inboundAddress: String
    /// Human-decimal amount, already validated against the wallet balance.
    let switchAmount: Decimal

    /// Rendered through the app's own locale-aware formatter, which is exactly
    /// what the legacy sub-model handed to `SendTransaction`. Downstream,
    /// `SendCryptoLogic.amountInRaw` reads this back with the matching
    /// locale-aware parse and scales it by `10^decimals`, so the string has to
    /// stay in the user's own convention — an ASCII-canonical `"1.5"` would be
    /// read as fifteen on a comma-decimal machine.
    var amount: String { switchAmount.formatToDecimal(digits: coin.decimals) }
    let sendMaxAmount: Bool = false

    var memo: String { "SWITCH:\(thorchainAddress)" }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("destinationAddress", inboundAddress)
        dict.set("thorchainAddress", thorchainAddress)
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    /// THORChain's inbound vault. A SWITCH is an ordinary `MsgSend` — the memo
    /// is only honoured because the recipient is the vault, so an empty or
    /// stale value here is a permanent loss rather than a failed transaction.
    var toAddress: String { inboundAddress }
}
