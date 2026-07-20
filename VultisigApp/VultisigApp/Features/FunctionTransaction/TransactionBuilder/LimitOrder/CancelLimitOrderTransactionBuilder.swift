//
//  CancelLimitOrderTransactionBuilder.swift
//  VultisigApp
//

import VultisigCommonData

/// Builds the THORChain `MsgDeposit` that cancels a resting limit order: an
/// `m=<` memo with a modified target of `0`, carrying **no coins at all**.
///
/// ⚠️ **Send a zero AMOUNT.** THORNode's modify handler donates any funds that
/// arrive with the transaction straight to the pool (`donateToPool`), so a
/// cancel carrying value is a cancel plus a silent, unrecoverable gift.
///
/// Precisely: the donation is gated on `!msg.DepositAmount.IsZero()`, **not** on
/// the coins array being non-empty. `getMsgModifyLimitSwap` populates
/// `DepositAsset`/`DepositAmount` whenever `len(tx.Tx.Coins) > 0`, but a
/// zero-amount coin makes `DepositAmount` zero and the donation is skipped. That
/// distinction matters here because the THORChain signer always emits a
/// one-element `coins` array — it omits only the *amount* when `toAmount == 0`
/// (`thorchain.swift`) — so "no coins at all" is not a shape this app can
/// produce, and does not need to be. The zero-amount MsgDeposits already in
/// production (UNBOND, LEAVE, TCY unstake) ride this exact path.
///
/// So `amount` is `"0"` and must stay that way. The THORChain deposit gas is
/// charged against the account separately (`DeductNativeTxFeeFromAccount`) and
/// never rides in the coin field.
///
/// ⚠️ **`memoFunctionDictionary` must be non-empty.** `SendCryptoLogic.isDeposit`
/// keys off that dictionary being populated, NOT off the memo, and a send that
/// is not a "deposit" is signed as a plain `MsgSend` — a 0-RUNE self-transfer
/// that broadcasts successfully, costs a fee, and does nothing at all. The
/// entries below exist to be shown on the verify screen, but at least one of
/// them also has to exist for the transaction to be built as a deposit.
struct CancelLimitOrderTransactionBuilder: TransactionBuilder {
    let coin: Coin
    /// Pre-built by `buildCancelLimitSwapMemo` from the exact integers recorded
    /// at signing. Passed in rather than rebuilt here so the eligibility check
    /// and the signed memo cannot disagree.
    let memo: String
    /// Shown on the verify screen so the user can see WHICH order is being
    /// cancelled — the memo alone is unreadable.
    let sourceAssetDisplay: String
    let targetAssetDisplay: String

    var amount: String { "0" }
    var sendMaxAmount: Bool { false }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("Action", "Cancel limit order")
        dict.set("From", sourceAssetDisplay)
        dict.set("To", targetAssetDisplay)
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    /// Empty, like every other THORChain `MsgDeposit` function call — the
    /// deposit's destination is the protocol module, resolved at signing.
    var toAddress: String { "" }
}
