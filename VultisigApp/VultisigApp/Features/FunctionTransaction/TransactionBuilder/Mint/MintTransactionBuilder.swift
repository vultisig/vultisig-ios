//
//  MintTransactionBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/11/2025.
//

import Foundation
import VultisigCommonData

struct MintTransactionBuilder: TransactionBuilder {
    static let destinationAddress = TCYAutoCompoundConstants.contract
    let coin: Coin
    let amount: String
    let sendMaxAmount: Bool

    var amountMicro: UInt64 {
        let decimals = coin.decimals
        let multiplier = pow(10.0, Double(decimals))
        let micro = (amount.toDecimal() * Decimal(multiplier)) as NSDecimalNumber
        return micro.uint64Value
    }

    var memo: String {
        "yVault-\(coin.ticker.uppercased())-deposit"
    }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("executeMsg", buildExecuteMsg())
        return dict
    }

    var transactionType: VSTransactionType {
        .genericContract
    }

    var wasmContractPayload: WasmExecuteContractPayload? {
        let cosmosCoin: CosmosCoin

        let denomKey = coin.ticker.lowercased()
        cosmosCoin = CosmosCoin(amount: String(amountMicro), denom: denomKey)

        return WasmExecuteContractPayload(
            senderAddress: coin.address,
            contractAddress: YVaultConstants.affiliateContractAddress,
            executeMsg: buildExecuteMsg(),
            coins: [cosmosCoin]
        )
    }

    private func buildExecuteMsg() -> String {
        let denom = coin.ticker.lowercased()
        let targetContract = YVaultConstants.contracts[denom] ?? ""

        let depositMsg = "{\"deposit\":{}}"
        let base64Msg = Data(depositMsg.utf8).base64EncodedString()
        return "{\"execute\":{\"contract_addr\":\"\(targetContract)\",\"msg\": \"\(base64Msg)\",\"affiliate\":[\"\(YVaultConstants.affiliateAddress)\",\(YVaultConstants.affiliateFeeBasisPoints)]}}"
    }

    var toAddress: String { YVaultConstants.affiliateContractAddress }
}
