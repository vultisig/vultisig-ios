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

    /// ⚠️ **Deliberately unnamed**, and asymmetric with the redeem side on
    /// purpose. `coin` here is what is SPENT — the RUNE or TCY going into the
    /// vault — while what is minted is the yCoin receipt, in a quantity this
    /// transaction does not know. The hero names one coin and one figure, so
    /// `.mint` would read "You're minting 10 RUNE" over a deposit of 10 RUNE that
    /// mints an unstated amount of yRUNE. "You're sending 10 RUNE" is at least
    /// true about the money leaving.
    ///
    /// Redeem is the mirror image and IS named: there `coin` is the yCoin being
    /// burned, so the verb and the figure agree.
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
