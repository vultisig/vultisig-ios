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
    /// The order being cancelled, resolved before navigation. Its `memo` was
    /// built by `buildCancelLimitSwapMemo` from the exact integers recorded at
    /// signing; carrying the whole request rather than just the memo keeps the
    /// order's identity attached, so a confirmed broadcast can be attributed
    /// back to the right row.
    let request: LimitOrderCancelRequest
    /// `nil` for a THORChain-sourced cancel (a `MsgDeposit` has no destination
    /// and attaches nothing). For an L1-sourced cancel, the Asgard inbound vault
    /// and the dust that must ride along for Bifrost to observe it.
    let l1Destination: LimitOrderCancelL1Destination?

    var memo: String { request.memo }
    var limitCancelContext: LimitOrderCancelRequest? { request }

    /// Zero for THORChain (see the donation note above). For L1 the dust is
    /// mandatory: Bifrost drops a zero-value transaction before it ever becomes
    /// a `MsgObservedTxIn`, so a cancel carrying nothing is simply never seen.
    var amount: String { l1Destination?.dustDecimalString ?? "0" }
    var sendMaxAmount: Bool { false }

    /// ⚠️ Populated ONLY for the THORChain route. **Do not "simplify" this to
    /// always-populated or always-empty — it breaks in a different way in each
    /// direction, and neither failure is visible from the call site.**
    ///
    /// `SendCryptoLogic.isDeposit` is "dictionary non-empty AND chain is not
    /// UTXO/Ripple/Solana".
    ///
    /// - Populate it for THORChain, or `isDeposit` is false and the `m=<` memo
    ///   is signed as a plain `MsgSend`: a 0-RUNE self-transfer that broadcasts
    ///   successfully, costs a fee, and cancels nothing.
    /// - Leave it EMPTY for an EVM L1 source, or `isDeposit` turns true for
    ///   Ethereum and the transaction is built as a THORChain deposit on a chain
    ///   that has no such message type.
    ///
    /// UTXO sources are excluded by chain type either way, so EVM is the case
    /// that actually depends on the empty branch — which is exactly why it looks
    /// removable and is not.
    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        guard l1Destination == nil else { return dict }
        dict.set("Action", "Cancel limit order")
        dict.set("From", request.sourceAsset)
        dict.set("To", request.targetAsset)
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    /// Empty for the THORChain route, like every other `MsgDeposit` function
    /// call — the destination is the protocol module, resolved at signing. For
    /// L1 it is the live Asgard inbound vault.
    var toAddress: String { l1Destination?.inboundAddress ?? "" }
}
