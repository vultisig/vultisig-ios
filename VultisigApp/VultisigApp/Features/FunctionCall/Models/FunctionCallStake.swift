//
//  FunctionCallStake.swift
//  VultisigApp
//
//  TON stake (memo "d") sub-model. Form-VM rewrite per the
//  FunctionCall sub-model rewrite workstream — owns `amount` and
//  `nodeAddress` directly. Reads `selectedCoin` from the screen via
//  `@Binding<Coin>` so the balance label updates when the active coin
//  changes upstream. The matching `StakeFormView` is co-located.
//

import BigInt
import Foundation
import SwiftUI

@Observable
@MainActor
final class FunctionCallStake {
    var amount: Decimal = 0
    var nodeAddress: String = ""
    var addressError: String?
    var customErrorMessage: String?

    init(initialAmount: Decimal = 0) {
        self.amount = initialAmount
    }

    func balance(for coin: Coin) -> String {
        let balance = coin.balanceDecimal.formatForDisplay()
        return "( Balance: \(balance) \(coin.ticker.uppercased()) )"
    }

    func validate(against coin: Coin) {
        let balance = coin.balanceDecimal
        if amount <= 0 {
            customErrorMessage = "insufficientBalanceForFunctions".localized
        } else if balance < amount {
            customErrorMessage = "insufficientBalanceForFunctions".localized
        } else {
            customErrorMessage = nil
        }
    }

    func isAmountValid(against coin: Coin) -> Bool {
        amount > 0 && amount <= coin.balanceDecimal
    }

    /// Submit-time validity gate. The active coin must be passed in so
    /// the amount-against-balance check is part of the same predicate
    /// the screen reads — no separate no-arg shape can drift past it.
    func isFormValid(for coin: Coin) -> Bool {
        isAmountValid(against: coin) &&
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
        "d"
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
        _ = isFastVault
        return SendTransaction.empty(coin: coin, vault: vault).copy(
            toAddress: nodeAddress,
            amount: amount.formatToDecimal(digits: coin.decimals),
            memo: toString(),
            gas: gas,
            transactionType: .unspecified,
            memoFunctionDictionary: toDictionary().allItems()
        )
    }
}

struct StakeFormView: View {
    @Bindable var model: FunctionCallStake
    @Binding var selectedCoin: Coin

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AddressTextField(
                address: $model.nodeAddress,
                label: "nodeAddress".localized,
                coin: selectedCoin,
                error: $model.addressError
            ) { result in
                model.handle(addressResult: result)
            }

            VStack(alignment: .leading, spacing: 8) {
                StyledFloatingPointField(
                    label: "amount".localized,
                    placeholder: "enterAmount".localized,
                    value: $model.amount,
                    isValid: .constant(true)
                )
                .onChange(of: model.amount) {
                    model.validate(against: selectedCoin)
                }

                Text(model.balance(for: selectedCoin))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let errorMessage = model.customErrorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
