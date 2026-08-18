//
//  BRUNEUnstakeTransactionBuilder.swift
//  VultisigApp
//

import Foundation
import VultisigCommonData

/// Unstake (unbond) builder for Rujira ybRUNE → bRUNE. Emits the
/// `{"liquid":{"unbond":{}}}` wasm execute against the bRUNE liquid-bond
/// contract, funded with the `x/staking-x/brune` receipt units being unbonded.
///
/// `coin` is the bRUNE bond coin (the DeFi card maps the ybRUNE compound
/// position back to bRUNE via `stakeCoin(for:)`); `autoCompoundAmount` is the
/// human-readable ybRUNE balance read on-chain from `x/staking-x/brune`. bRUNE
/// and ybRUNE share 8 decimals, so scaling the withdrawn fraction with the bRUNE
/// coin yields the correct receipt base units.
struct BRUNEUnstakeTransactionBuilder: TransactionBuilder {
    static let destinationAddress = BRUNEStakingConstants.contract
    let coin: Coin
    /// What the user asked to unbond, in the units the sheet was denominated in.
    ///
    /// Those units are ybRUNE receipt units: the staked card renders the receipt
    /// balance directly, so this figure and `autoCompoundAmount` are the same
    /// kind of thing (see `UnstakeTransactionViewModel.receiptBalanceIsAvailableAmount`).
    /// It is converted against `stakedAmount` all the same rather than assumed —
    /// see `ReceiptShareRedemption`.
    let withdrawAmount: Decimal
    /// The position the sheet was showing — the balance `withdrawAmount` is a
    /// share of, in the same units.
    let stakedAmount: Decimal
    let autoCompoundAmount: Decimal
    let sendMaxAmount: Bool

    var amount: String { "0" }

    var memo: String { "" }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .genericContract }

    /// The `x/staking-x/brune` base units this unbond is funded with — the whole
    /// of the instruction, since the execute message itself is empty.
    ///
    /// Converted straight from the typed amount. It used to be reached through
    /// `Int(percentage)`, which floored a step to a whole 1% of the position and
    /// silently unbonded ~20 ybRUNE less than was asked for on a 2002.74 position;
    /// the funds carry an absolute count, so there was never a coarse step to
    /// round to. `ReceiptShareRedemption` holds the arithmetic and the guards.
    var redeemedUnits: Decimal {
        ReceiptShareRedemption.baseUnits(
            forAmount: withdrawAmount,
            positionValue: stakedAmount,
            receiptBaseUnits: coin.decimalToCrypto(value: autoCompoundAmount),
            closingPosition: sendMaxAmount
        )
    }

    var wasmContractPayload: WasmExecuteContractPayload? {
        // A redemption funded with nothing pays a fee to unbond nothing. The
        // amount field's own validators normally stop it reaching here.
        //
        // ⚠️ Kept in `Decimal` rather than routed through `Decimal.toInt()`. That
        // wraps outside signed 64-bit range, and the receipt balance is parsed as
        // `UInt64` — so a position above `Int.max` base units would render as a
        // negative count, fail this guard, and become unwithdrawable at MAX.
        // `wholeUnits` has already made this an integer, so its description is
        // the digits and nothing else.
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
                denom: TokensStore.ybrune.contractAddress
            )]
        )
    }

    var toAddress: String { "" }
}
