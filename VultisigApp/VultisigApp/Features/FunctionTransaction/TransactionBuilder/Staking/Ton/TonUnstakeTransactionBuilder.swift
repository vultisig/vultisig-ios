//
//  TonUnstakeTransactionBuilder.swift
//  VultisigApp
//

import VultisigCommonData
import WalletCore

/// Builds a TON nominator-pool unstake transaction: send a small fixed amount
/// of TON to the pool contract with the pool's withdraw text comment. Nominator
/// pools support full withdrawal only, so no amount is taken from the user — the
/// withdraw message triggers the full withdrawal. The comment is
/// implementation-specific ("w" for standard `tf` pools, "Withdraw" for
/// `whales` pools), so it is resolved by the caller and passed in.
struct TonUnstakeTransactionBuilder: TransactionBuilder {
    let coin: Coin
    /// Amount accompanying the withdraw message (the 0.2 TON withdraw fee). The
    /// pool returns the staked balance separately.
    let amount: String
    let sendMaxAmount: Bool = false
    let poolAddress: String

    /// Withdraw text comment the pool contract expects, resolved from the pool
    /// implementation (`whales` → "Withdraw", `tf` → "w").
    let memo: String

    /// Sent bounceable (`EQ…`) so a rejected withdrawal message returns the
    /// accompanying TON instead of being absorbed by the pool. Pool addresses
    /// arrive in raw `0:` form, which the signer treats as non-bounceable.
    var bounceablePoolAddress: String {
        TONAddressConverter.toUserFriendly(address: poolAddress, bounceable: true, testnet: false) ?? poolAddress
    }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", bounceablePoolAddress)
        dict.set("memo", memo)
        return dict
    }

    /// ⚠️ **Deliberately unnamed.** `amount` is the 0.2 TON withdrawal signal
    /// the pool contract requires, not the position being withdrawn — the pool
    /// returns the staked balance separately, and nominator pools only do full
    /// withdrawals. "You're unstaking 0.2 TON" would misname the fee as the
    /// position, and a hero quoting the staked balance instead would remove the
    /// only place that 0.2 TON is shown to the user at all. Naming this needs the
    /// staked figure AND a disclosure row for the signal, like the limit-order
    /// cancel's donated dust.
    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    var toAddress: String { bounceablePoolAddress }
}
