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
/// Redeeming a share of the position is driven by the percentage rather than by
/// a RUJI amount, which sidesteps the share-price conversion entirely: at 100%
/// the exact held share balance is redeemed, so there is no rounding dust and it
/// can never exceed what is held even if the share price moved since the sheet
/// opened.
struct RUJILiquidUnbondTransactionBuilder: TransactionBuilder {
    static let destinationAddress = RUJIStakingConstants.contract
    let coin: Coin
    let percentage: Int
    let receiptShares: Decimal
    let sendMaxAmount: Bool

    var amount: String { "0" }

    var memo: String { "" }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .genericContract }

    var wasmContractPayload: WasmExecuteContractPayload? {
        let redeemed = (coin.decimalToCrypto(value: receiptShares) * Decimal(percentage)) / 100
        // Rounds DOWN to whole base units: redeeming more shares than are held
        // would fail on-chain, and a fractional `CosmosCoin.amount` is malformed.
        let units = redeemed.toInt()
        guard units >= 1 else { return nil }

        return WasmExecuteContractPayload(
            senderAddress: coin.address,
            contractAddress: Self.destinationAddress,
            executeMsg: """
            { "liquid": { "unbond": {} } }
            """,
            coins: [CosmosCoin(
                amount: String(units),
                denom: TokensStore.sruji.contractAddress
            )]
        )
    }

    var toAddress: String { "" }
}
