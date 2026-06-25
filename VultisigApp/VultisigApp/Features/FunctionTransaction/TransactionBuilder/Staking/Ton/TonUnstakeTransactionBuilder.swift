//
//  TonUnstakeTransactionBuilder.swift
//  VultisigApp
//

import VultisigCommonData
import WalletCore

/// Builds a TON nominator-pool unstake transaction: send a small fixed amount
/// of TON to the pool contract with the text comment "w". Standard nominator
/// pools support full withdrawal only, so no amount is taken from the user —
/// the "w" message triggers the full withdrawal.
struct TonUnstakeTransactionBuilder: TransactionBuilder {
    let coin: Coin
    /// Amount accompanying the "w" message (1 TON). The pool returns the
    /// staked balance separately.
    let amount: String
    let sendMaxAmount: Bool = false
    let poolAddress: String

    let memo: String = "w"

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

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    var toAddress: String { bounceablePoolAddress }
}
