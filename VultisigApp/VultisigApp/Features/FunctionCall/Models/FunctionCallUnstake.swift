//
//  FunctionCallUnstake.swift
//  VultisigApp
//
//  TON unstake memo sub-model. Form-VM rewrite per the FunctionCall
//  sub-model rewrite workstream — owns `amount` + `nodeAddress`
//  directly. The matching `UnstakeFormView` is co-located in this
//  file.
//

import BigInt
import Foundation
import SwiftUI

@Observable
@MainActor
final class FunctionCallUnstake {
    var amount: Decimal = 1
    var nodeAddress: String = ""
    var addressError: String?
    var customErrorMessage: String?

    init() {}

    var isTheFormValid: Bool {
        amount > 0 && FunctionCallAddressValidation.isValidThorMayaTON(nodeAddress)
    }

    func handle(addressResult: AddressResult?) {
        guard let addressResult else { return }
        nodeAddress = addressResult.address
    }

    var description: String {
        toString()
    }

    func toString() -> String {
        "w"
    }

    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", nodeAddress)
        dict.set("memo", toString())
        return dict
    }

    func toSendTransaction(
        coin: Coin,
        vault: Vault,
        gas: BigInt,
        isFastVault: Bool
    ) -> SendTransaction {
        SendTransaction.empty(coin: coin, vault: vault).copy(
            toAddress: nodeAddress,
            amount: amount.formatToDecimal(digits: coin.decimals),
            memo: toString(),
            gas: gas,
            transactionType: .unspecified,
            memoFunctionDictionary: toDictionary().allItems()
        )
    }
}

struct UnstakeFormView: View {
    @Bindable var model: FunctionCallUnstake
    let coin: Coin

    var body: some View {
        VStack {
            AddressTextField(
                address: $model.nodeAddress,
                label: "nodeAddress".localized,
                coin: coin,
                error: $model.addressError
            ) { result in
                model.handle(addressResult: result)
            }

            StyledFloatingPointField(
                label: "amount".localized,
                placeholder: "enterAmount".localized,
                value: $model.amount,
                isValid: .constant(true)
            )
        }
    }
}
