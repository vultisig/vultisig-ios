//
//  BRUNEUnstakeTransactionBuilder.swift
//  VultisigApp
//

import Foundation
import VultisigCommonData

/// Unstake (unbond) builder for Rujira ybRUNE → bRUNE. Emits the
/// `{"liquid":{"unbond":{}}}` wasm execute against the bRUNE liquid-bond
/// contract, funded with the `x/staking-x/brune` receipt units being unbonded.
///
/// `coin` is the bRUNE bond coin (the DeFi card maps the ybRUNE compound
/// position back to bRUNE via `stakeCoin(for:)`); `autoCompoundAmount` is the
/// human-readable ybRUNE balance read on-chain from `x/staking-x/brune`. bRUNE
/// and ybRUNE share 8 decimals, so scaling the withdrawn fraction with the bRUNE
/// coin yields the correct receipt base units.
struct BRUNEUnstakeTransactionBuilder: TransactionBuilder {
    static let destinationAddress = BRUNEStakingConstants.contract
    let coin: Coin
    let percentage: Int
    let autoCompoundAmount: Decimal
    let sendMaxAmount: Bool

    var amount: String { "0" }

    /// ⚠️ **Names no figure.** The redemption spends `x/staking-x/brune`
    /// receipt units, which are worth more than 1 bRUNE each and drift as the
    /// pool compounds, so a fraction of the share count is not the payout. The
    /// hero stays suppressed rather than quoting one — same call as the TCY and
    /// RUJI auto-compounding positions.
    var functionKind: FunctionTransactionKind? { .unstake }

    var memo: String { "" }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .genericContract }

    var wasmContractPayload: WasmExecuteContractPayload? {
        let withdrawAmount = (coin.decimalToCrypto(value: autoCompoundAmount) * Decimal(percentage)) / 100
        let units = withdrawAmount.toInt()
        guard units >= 1 else { return nil }

        return WasmExecuteContractPayload(
            senderAddress: coin.address,
            contractAddress: Self.destinationAddress,
            executeMsg: """
            { "liquid": { "unbond": {} } }
            """,
            coins: [CosmosCoin(
                amount: String(units),
                denom: TokensStore.ybrune.contractAddress
            )]
        )
    }

    var toAddress: String { "" }
}
