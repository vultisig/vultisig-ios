//
//  CosmosDelegateTransactionBuilder.swift
//  VultisigApp
//
//  Per-flow builder for LUNA / LUNC `MsgDelegate`. The builder is a pure
//  value-type carrier; SignDoc bytes are produced lazily by
//  `CosmosStakingSignDataResolver.resolve(...)` at Verify → KeysignPayload
//  bridge time so the chain-specific account/sequence are always fresh.
//
//  Mirrors the shape of `BondMayaTransactionBuilder` — `memo = ""` (cosmos
//  staking msgs carry no memo), `transactionType = .unspecified`, real
//  payload travels via the `cosmosStakingPayload` accessor.
//

import BigInt
import Foundation
import VultisigCommonData

struct CosmosDelegateTransactionBuilder: TransactionBuilder {
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
    /// `toAddress` doubles as the verify-screen "destination" — for delegate
    /// flows the operator (`terravaloper1…`) is what the user is sending
    /// stake to.
    var toAddress: String { validatorAddress }

    var cosmosStakingPayload: CosmosStakingPayload? {
        let denom = (try? CosmosStakingConfig.bondDenom(for: coin.chain)) ?? ""
        let baseAmount = baseUnitsString(amount: amount, decimals: coin.decimals)
        return CosmosStakingPayload.delegate(
            validator: validatorAddress,
            denom: denom,
            amount: baseAmount
        )
    }

    /// Converts a human-decimal amount string (e.g. `"1.5"`) to the
    /// chain's base-unit string (e.g. `"1500000"` for LUNA 6-decimals).
    /// Decimal-based to avoid floating-point drift across the boundary.
    private func baseUnitsString(amount: String, decimals: Int) -> String {
        let normalized = amount.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Decimal(string: normalized) else { return "0" }
        let multiplier = pow(Decimal(10), decimals)
        let raw = parsed * multiplier
        let handler = NSDecimalNumberHandler(
            roundingMode: .down,
            scale: 0,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        return NSDecimalNumber(decimal: raw).rounding(accordingToBehavior: handler).stringValue
    }
}
