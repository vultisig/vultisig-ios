//
//  TonStakeTransactionBuilder.swift
//  VultisigApp
//

import VultisigCommonData
import WalletCore

/// Builds a TON nominator-pool stake transaction: send `amount` TON to the pool
/// contract with the pool's deposit text comment. The comment is
/// implementation-specific ("d" for standard `tf` pools, "Stake" for `whales`
/// pools), so it is resolved by the caller and passed in rather than hardcoded.
struct TonStakeTransactionBuilder: TransactionBuilder {
    let coin: Coin
    let amount: String
    let sendMaxAmount: Bool = false
    let poolAddress: String

    /// Deposit text comment the pool contract expects, resolved from the pool
    /// implementation (`whales` → "Stake", `tf` → "d").
    let memo: String

    /// Pool deposits MUST be sent bounceable (`EQ…`) so a rejected deposit
    /// (e.g. below the pool's effective minimum) bounces the TON back to the
    /// vault instead of being absorbed by the pool contract. Staking-API pool
    /// addresses arrive in raw `0:` form, which the signer treats as
    /// non-bounceable — so normalize to the bounceable user-friendly form here.
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
