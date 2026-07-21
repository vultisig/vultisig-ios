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

    var memo: String { "" }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .genericContract }

    var wasmContractPayload: WasmExecuteContractPayload? {
        // Rounds DOWN to whole base units of `x/ruji`: the amount field does not
        // cap to the coin's 8 dp, and `CosmosCoin.amount` must be an integer
        // base-unit string or the execute is malformed. Never round up — funding
        // more base units than held would fail on-chain.
        let units = coin.decimalToCrypto(value: amount.toDecimal()).toInt()
        // Sub-base-unit dust truncates to zero, which the amount validator lets
        // through (it only rejects an exact zero). Bonding zero funds is a no-op
        // that still costs a fee, so refuse to build it. Mirrors the unbond side.
        guard units >= 1 else { return nil }

        return WasmExecuteContractPayload(
            senderAddress: coin.address,
            contractAddress: Self.destinationAddress,
            executeMsg: """
            { "liquid": { "bond": {} } }
            """,
            coins: [CosmosCoin(
                amount: String(units),
                denom: coin.contractAddress
            )]
        )
    }

    var toAddress: String { "" }
}
