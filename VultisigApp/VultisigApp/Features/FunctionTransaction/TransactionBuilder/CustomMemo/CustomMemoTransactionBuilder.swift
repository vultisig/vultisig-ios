//
//  CustomMemoTransactionBuilder.swift
//  VultisigApp
//
//  The raw-memo escape hatch: an arbitrary THORChain / MayaChain `MsgDeposit`,
//  carrying a memo the app does not understand and an optional amount of one of
//  the vault's own coins on that chain.
//
//  It exists because the protocols keep shipping memo operations faster than
//  the app grows forms for them, and because support walks users through
//  one-off deposits with it. Every other builder in this tree composes a memo
//  from typed fields; this one is the only place a string reaches the chain
//  exactly as it was typed.
//

import Foundation
import VultisigCommonData

struct CustomMemoTransactionBuilder: TransactionBuilder {
    /// The asset the deposit rides on — one of the vault's coins on the chain
    /// the form is running on, never a ticker the vault does not hold.
    let coin: Coin
    /// The user's memo, byte for byte.
    let customMemo: String
    /// Human-decimal amount. Zero for the memo-only deposits that are most of
    /// this form's traffic.
    let customAmount: Decimal

    /// **Verbatim.** No trimming, no case folding, no escaping, no separator
    /// normalisation. A custom memo is by definition a string the app has no
    /// grammar for: every transformation is a way to turn an operation the user
    /// meant into one they did not. The blank-memo check lives in the form's
    /// validity gate, which is a decision about whether to submit at all — it
    /// never rewrites what is submitted.
    var memo: String { customMemo }

    /// Rendered through the app's own locale-aware formatter, which is exactly
    /// what the legacy sub-model handed to `SendTransaction`. Downstream,
    /// `SendCryptoLogic.amountInRaw` reads this back with the matching
    /// locale-aware parse and scales it by `10^decimals`, so the string has to
    /// stay in the user's own convention — an ASCII-canonical `"1.5"` would be
    /// read as fifteen on a comma-decimal machine.
    var amount: String { customAmount.formatToDecimal(digits: coin.decimals) }
    let sendMaxAmount: Bool = false

    /// One entry, matching the legacy sub-model's dictionary exactly: the
    /// verify screen renders these rows, and an invented key would show the
    /// user a field the transaction does not have.
    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    /// Empty: a `MsgDeposit` is addressed by its memo, not by a recipient.
    var toAddress: String { .empty }
}
