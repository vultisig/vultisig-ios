//
//  CosmosRedelegateTransactionBuilder.swift
//  VultisigApp
//
//  Per-flow builder for LUNA / LUNC `MsgBeginRedelegate`. Wire-shape on
//  the cosmos staking module differs from delegate/undelegate — the Coin
//  field is `(4)` and there are two validator addresses (source / dest)
//  in fields `(2)` and `(3)`. The byte order is enforced inside
//  `CosmosStakingHelper.encodeBeginRedelegate(...)`; the builder only
//  carries intent.
//
//  Cooldown gating (the cosmos-sdk x/staking module enforces 21 days
//  per `src → *` pair) lives in `CosmosRedelegationCooldownGate.swift`
//  and is evaluated in the redelegate view-model BEFORE the user can
//  navigate to Verify — so a blocked redelegation never burns an MPC
//  ceremony.
//

import BigInt
import Foundation
import VultisigCommonData

struct CosmosRedelegateTransactionBuilder: TransactionBuilder {
    let coin: Coin
    let amount: String
    let sendMaxAmount: Bool
    let validatorSrcAddress: String
    let validatorDstAddress: String

    var memo: String { "" }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        ThreadSafeDictionary<String, String>()
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    /// `toAddress` doubles as the verify-screen "destination" — for
    /// redelegate the user is moving stake to the destination valoper.
    var toAddress: String { validatorDstAddress }

    var cosmosStakingPayload: CosmosStakingPayload? {
        let denom = (try? CosmosStakingConfig.bondDenom(for: coin.chain)) ?? ""
        let baseAmount = CosmosStakingAmountFormatter.baseUnitsString(
            amount: amount,
            decimals: coin.decimals
        )
        return CosmosStakingPayload.redelegate(
            src: validatorSrcAddress,
            dst: validatorDstAddress,
            denom: denom,
            amount: baseAmount
        )
    }
}
