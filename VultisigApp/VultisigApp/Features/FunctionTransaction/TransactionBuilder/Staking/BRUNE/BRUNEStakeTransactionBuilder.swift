//
//  BRUNEStakeTransactionBuilder.swift
//  VultisigApp
//

import VultisigCommonData

/// Stake (bond) builder for Rujira bRUNE → ybRUNE. Emits the
/// `{"liquid":{"bond":{}}}` wasm execute against the bRUNE liquid-bond contract,
/// funded with the bonded `x/brune` amount.
///
/// bRUNE staking is always the auto-compounding liquid bond (there is no
/// memo-based native path, unlike TCY), so this builder always produces the
/// wasm payload and a `.genericContract` transaction type.
struct BRUNEStakeTransactionBuilder: TransactionBuilder {
    static let destinationAddress = BRUNEStakingConstants.contract
    let coin: Coin
    let amount: String
    let sendMaxAmount: Bool

    /// Bonded amount in whole base units of the `x/brune` denom (8 dp).
    ///
    /// Rounds DOWN to an integer: `decimalToCrypto` (×10^decimals) leaves a
    /// fractional `Decimal` when the entered amount exceeds the coin's precision
    /// (the amount field does not cap to 8 dp), and `CosmosCoin.amount` must be an
    /// integer base-unit string or the wasm execute is malformed. Never round up —
    /// funding more base units than held would fail on-chain. Mirrors the unstake
    /// builder's `.toInt()`.
    var rawAmount: String {
        String(coin.decimalToCrypto(value: amount.toDecimal()).toInt())
    }

    var memo: String { "" }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .genericContract }

    var wasmContractPayload: WasmExecuteContractPayload? {
        WasmExecuteContractPayload(
            senderAddress: coin.address,
            contractAddress: Self.destinationAddress,
            executeMsg: """
            { "liquid": { "bond": {} } }
            """,
            coins: [CosmosCoin(
                amount: rawAmount,
                denom: coin.contractAddress
            )]
        )
    }

    var toAddress: String { "" }
}
