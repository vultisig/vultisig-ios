//
//  RUJILiquidBondTransactionBuilder.swift
//  VultisigApp
//

import Foundation
import VultisigCommonData

/// Stake builder for the AUTO-COMPOUNDING RUJI position: emits the
/// `{"liquid":{"bond":{}}}` wasm execute against the RUJI staking contract,
/// funded with `x/ruji`, and mints the sRUJI receipt in return. The bonded
/// position is a different message and keeps using `RUJIStakeTransactionBuilder`.
///
/// Both actions bond RUJI, so routing them to the same message would silently
/// move the user's funds into the other position — the one whose card they did
/// not tap, with different rewards and a different unstake path.
struct RUJILiquidBondTransactionBuilder: TransactionBuilder {
    static let destinationAddress = RUJIStakingConstants.contract
    let coin: Coin
    let amount: String
    let sendMaxAmount: Bool

    /// Bonded amount in whole base units of `x/ruji`. Rounds DOWN: the amount
    /// field does not cap to the coin's 8 dp, and `CosmosCoin.amount` must be an
    /// integer base-unit string or the execute is malformed. Never round up —
    /// funding more base units than held would fail on-chain.
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
