//
//  CosmosUndelegateTransactionBuilder.swift
//  VultisigApp
//
//  Per-flow builder for LUNA / LUNC `MsgUndelegate`. Identical shape to the
//  delegate builder — only the `cosmosStakingPayload.opType` distinguishes
//  the two at SignDoc-encoding time. The cosmos x/staking unbonding period
//  on both Terra chains is 21 days; the UI surfaces a "Unbonds %@" lock
//  notice on the Verify screen via the staking payload.
//

import BigInt
import Foundation
import VultisigCommonData

struct CosmosUndelegateTransactionBuilder: TransactionBuilder {
    let coin: Coin
    let amount: String
    let sendMaxAmount: Bool
    let validatorAddress: String

    var memo: String { "" }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        ThreadSafeDictionary<String, String>()
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    var toAddress: String { validatorAddress }

    var cosmosStakingPayload: CosmosStakingPayload? {
        let denom = (try? CosmosStakingConfig.bondDenom(for: coin.chain)) ?? ""
        let baseAmount = CosmosStakingAmountFormatter.baseUnitsString(
            amount: amount,
            decimals: coin.decimals
        )
        return CosmosStakingPayload.undelegate(
            validator: validatorAddress,
            denom: denom,
            amount: baseAmount
        )
    }
}
