//
//  RUJIWithdrawRewardsTransactionBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/11/2025.
//

import Foundation
import VultisigCommonData

struct RUJIWithdrawRewardsTransactionBuilder: TransactionBuilder {
    static let destinationAddress = RUJIStakingConstants.contract
    let coin: Coin
    let withdrawAmount: String
    let sendMaxAmount: Bool
    let amount: String = "0"

    /// ⚠️ **Names no figure, and `withdrawAmount` is not the one to name.** RUJI
    /// staking pays its revenue in USDC (`THORChainStakingService` builds the
    /// rewards coin as USDC), while this builder's `coin` — and therefore the
    /// ticker any hero would render beside the amount — is RUJI. Quoting
    /// `withdrawAmount` here would read "claiming 12.34 RUJI" over a claim of
    /// 12.34 USDC, which is a worse sentence than the generic one it replaces.
    ///
    /// Naming it properly needs the hero to carry the reward COIN as well as the
    /// figure, which the single-coin shape does not do today.
    var functionKind: FunctionTransactionKind? { .claimRewards }

    var rawAmount: String {
        coin.decimalToCrypto(value: withdrawAmount.toDecimal()).description
    }

    var memo: String {
        return "claim:\(coin.contractAddress):\(rawAmount)"
    }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType {
        .genericContract
    }

    var wasmContractPayload: WasmExecuteContractPayload? {
        WasmExecuteContractPayload(
            senderAddress: coin.address,
            contractAddress: Self.destinationAddress,
            executeMsg: """
            { "account": { "claim": {} } }
            """,
            coins: []
        )
    }
    var toAddress: String { Self.destinationAddress }
}
