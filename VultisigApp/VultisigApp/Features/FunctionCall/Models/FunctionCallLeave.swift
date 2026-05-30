//
//  FunctionCallLeave.swift
//  VultisigApp
//
//  THORChain LEAVE memo sub-model. Form-VM rewrite per the FunctionCall
//  sub-model rewrite workstream — drops `FunctionCallAddressable`
//  conformance, owns its single `nodeAddress` field directly, and emits
//  the immutable `SendTransaction` via `toSendTransaction(...)` at the
//  navigation boundary. The matching `LeaveFormView` is co-located in
//  this file.
//

import BigInt
import Foundation
import SwiftUI

@Observable
@MainActor
final class FunctionCallLeave {
    var nodeAddress: String = ""
    var addressError: String?
    var customErrorMessage: String?

    init() {}

    var isTheFormValid: Bool {
        FunctionCallAddressValidation.isValidThorMayaTON(nodeAddress)
    }

    func handle(addressResult: AddressResult?) {
        guard let addressResult else { return }
        nodeAddress = addressResult.address
    }

    var description: String {
        toString()
    }

    func toString() -> String {
        "LEAVE:\(nodeAddress)"
    }

    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", nodeAddress)
        dict.set("memo", toString())
        return dict
    }

    /// Amount emitted on the immutable `SendTransaction`. LEAVE
    /// transactions burn zero RUNE — the validator unbonds via the memo
    /// alone, no asset transfer is required.
    var amount: Decimal { .zero }

    func toSendTransaction(
        coin: Coin,
        vault: Vault,
        gas: BigInt
    ) -> SendTransaction {
        return SendTransaction.empty(coin: coin, vault: vault).copy(
            amount: amount.formatToDecimal(digits: coin.decimals),
            memo: toString(),
            gas: gas,
            transactionType: .unspecified,
            memoFunctionDictionary: toDictionary().allItems()
        )
    }
}

struct LeaveFormView: View {
    @Bindable var model: FunctionCallLeave
    @Binding var selectedCoin: Coin

    var body: some View {
        VStack {
            AddressTextField(
                address: $model.nodeAddress,
                label: "nodeAddress".localized,
                coin: selectedCoin,
                error: $model.addressError
            ) { result in
                model.handle(addressResult: result)
            }
        }
    }
}
