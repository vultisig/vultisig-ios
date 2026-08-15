//
//  SecuredWithdrawTransactionBuilder.swift
//  VultisigApp
//
//  THORChain secured-asset redemption (`SECURE-`). The memo names the L1
//  address the protocol pays out to; the amount is genuinely attached, because
//  a redemption burns the secured balance the deposit carries. That makes it
//  the opposite of the node memos next door, where the attached amount is a
//  fund-safety zero.
//

import Foundation
import VultisigCommonData

struct SecuredWithdrawTransactionBuilder: TransactionBuilder {
    /// The secured asset being redeemed — a non-native THORChain token whose
    /// `contractAddress` is the dash-notation denom (`btc-btc`). It has to be
    /// this coin and not the vault's RUNE: `buildThorchainDepositMessage`
    /// derives `asset.chain` / `asset.symbol` / `asset.secured` straight off
    /// the denom, so a RUNE-shaped deposit would name an asset the node has no
    /// secured balance for.
    let coin: Coin
    /// The payout address, on the secured asset's OWN L1 chain — a Bitcoin
    /// address for `btc-btc`, an Ethereum one for `eth-usdc-…`.
    let destinationAddress: String
    let withdrawAmount: Decimal

    /// A human decimal, which is what `SendTransaction.amountInRaw` multiplies
    /// by `10^decimals`. Pinned to the legacy sub-model's
    /// `amount.formatToDecimal(digits: coin.decimals)` down to the truncation
    /// and the locale separators, because this is the number that leaves the
    /// vault.
    var amount: String { withdrawAmount.formatToDecimal(digits: coin.decimals) }
    let sendMaxAmount: Bool = false

    var memo: String { "SECURE-:\(destinationAddress)" }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("operation", "withdraw")
        dict.set("memo", memo)
        dict.set("destinationAddress", destinationAddress)
        return dict
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    /// Empty even though a destination exists: the redemption is a
    /// `MsgDeposit`, addressed by its memo. The destination travels in the
    /// memo and nowhere else — the legacy sub-model pinned the same emptiness.
    var toAddress: String { .empty }
}
