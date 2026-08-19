//
//  RUJILiquidUnbondTransactionBuilder.swift
//  VultisigApp
//

import Foundation
import VultisigCommonData

/// Unstake builder for the AUTO-COMPOUNDING RUJI position: emits the
/// `{"liquid":{"unbond":{}}}` wasm execute against the RUJI staking contract,
/// funded with the `x/staking-x/ruji` receipt shares being redeemed. The message
/// itself carries no amount — the funds do. The bonded position is a different
/// message entirely and keeps using `RUJIUnstakeTransactionBuilder`.
///
/// `coin` is the RUJI bond coin (the compounded card maps sRUJI back to RUJI via
/// `stakeCoin(for:)`); `receiptShares` is the human-readable on-chain
/// `x/staking-x/ruji` balance. RUJI and sRUJI share 8 decimals, so scaling the
/// redeemed fraction with the RUJI coin yields the right receipt base units.
///
/// ⚠️ **The amount and the receipt are different units.** The compounded card
/// renders `stakedAmount` — what the receipt is WORTH in RUJI, the pool's liquid
/// size — so that is what the sheet's balance and the typed amount are priced in,
/// while the funds are a count of shares worth more than 1 RUJI each. The two
/// balances the sheet was opened with are the redemption ratio between them, and
/// `ReceiptShareRedemption` is where the conversion and its guards live. A full
/// exit still redeems the exact held share balance, pinned rather than derived,
/// so it can neither leave dust behind nor exceed what is held if the share price
/// moved since the sheet opened.
struct RUJILiquidUnbondTransactionBuilder: TransactionBuilder {
    static let destinationAddress = RUJIStakingConstants.contract
    let coin: Coin
    /// What the user asked to redeem, priced in RUJI like the card it was typed
    /// under.
    let withdrawAmount: Decimal
    /// The RUJI the position is worth — the balance `withdrawAmount` is a share
    /// of, and the figure the verify screen quotes a fraction of.
    let stakedAmount: Decimal
    let receiptShares: Decimal
    let sendMaxAmount: Bool

    var amount: String { "0" }

    /// The RUJI this redemption pays out, quantised to the shares it actually
    /// spends — so the Verify screen states a figure instead of falling through to
    /// the generic header with none. `amount` is the literal `"0"`; the funds are
    /// the instruction. See `QuotedWithdrawalPresentation`.
    ///
    /// ⚠️ **A projection from two reads, not a commitment.** `stakedAmount` comes
    /// from the persisted DeFi card; `receiptShares` (behind `heldUnits`) is a
    /// separate live read. If they disagree the figure moves with them — the
    /// accepted shape of a fractional withdrawal, and it never claims more than was
    /// asked because the share count is truncated (`ReceiptShareRedemptionTests`).
    var withdrawDisplayAmount: Decimal? {
        let held = heldUnits
        let redeemed = redeemedUnits
        guard stakedAmount > 0, held >= 1, redeemed >= 1 else { return nil }
        return (stakedAmount * redeemed) / held
    }

    var memo: String { "" }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .genericContract }

    /// The whole `x/staking-x/ruji` base units held — the denominator the payout
    /// projection is a share of, and the ceiling the redemption clamps to.
    var heldUnits: Decimal {
        ReceiptShareRedemption.wholeUnits(coin.decimalToCrypto(value: receiptShares))
    }

    /// The `x/staking-x/ruji` base units this redemption is funded with — the
    /// whole of the instruction, since the execute message itself is empty.
    ///
    /// Converted straight from the typed amount. It used to be reached through
    /// `Int(percentage)`, which floored a step to a whole 1% of the position; the
    /// funds carry an absolute share count, so there was never a coarse step to
    /// round to.
    var redeemedUnits: Decimal {
        ReceiptShareRedemption.baseUnits(
            forAmount: withdrawAmount,
            positionValue: stakedAmount,
            receiptBaseUnits: coin.decimalToCrypto(value: receiptShares),
            closingPosition: sendMaxAmount
        )
    }

    var wasmContractPayload: WasmExecuteContractPayload? {
        // A redemption funded with nothing pays a fee to unbond nothing. The
        // amount field's own validators normally stop it reaching here.
        //
        // ⚠️ Kept in `Decimal` rather than routed through `Decimal.toInt()` —
        // see the bRUNE sibling for why a 64-bit round trip can make a large
        // position unwithdrawable.
        let units = redeemedUnits
        guard units >= 1 else { return nil }

        return WasmExecuteContractPayload(
            senderAddress: coin.address,
            contractAddress: Self.destinationAddress,
            executeMsg: """
            { "liquid": { "unbond": {} } }
            """,
            coins: [CosmosCoin(
                amount: units.description,
                denom: TokensStore.sruji.contractAddress
            )]
        )
    }

    var toAddress: String { "" }
}
