//
//  FunctionCallReBond.swift
//  VultisigApp
//
//  THORChain REBOND sub-model. Form-VM rewrite per the FunctionCall
//  sub-model rewrite workstream — owns two address fields + an
//  optional rebond amount directly. The RUNE-pin that previously
//  lived inside `initialize()` is hoisted to
//  `FunctionCallDetailsScreen.setData()` so the sub-model becomes a
//  pure value-reader. The matching `ReBondFormView` is co-located.
//

import BigInt
import Foundation
import SwiftUI

@Observable
@MainActor
final class FunctionCallReBond {
    var rebondAmount: Decimal = 0.0
    var nodeAddress: String = ""
    var newAddress: String = ""
    var nodeAddressError: String?
    var newAddressError: String?
    var customErrorMessage: String?

    init() {}

    /// REBOND transactions burn zero RUNE — the amount is only encoded
    /// in the memo, not in the on-chain transfer. Matches the legacy
    /// `FunctionCallInstance.amount` switch for `.rebond`.
    var amount: Decimal { .zero }

    func balance(for coin: Coin) -> String {
        let balance = coin.balanceDecimal.formatForDisplay()
        return "( Balance: \(balance) \(coin.ticker.uppercased()) )"
    }

    func validate(against coin: Coin) {
        if coin.chain != .thorChain || !coin.isNativeToken {
            customErrorMessage = "rebondRequiresRune".localized
        } else {
            customErrorMessage = nil
        }
    }

    var isTheFormValid: Bool {
        rebondAmount >= 0 &&
        FunctionCallAddressValidation.isValidThorMayaTON(nodeAddress) &&
        FunctionCallAddressValidation.isValidThorMayaTON(newAddress)
    }

    func handle(nodeAddressResult: AddressResult?) {
        guard let result = nodeAddressResult else { return }
        nodeAddress = result.address
    }

    func handle(newAddressResult: AddressResult?) {
        guard let result = newAddressResult else { return }
        newAddress = result.address
    }

    var description: String {
        toString()
    }

    func toString() -> String {
        var memo = "REBOND:\(nodeAddress):\(newAddress)"
        if rebondAmount > 0 {
            let amountInSmallestUnit = NSDecimalNumber(decimal: rebondAmount)
                .multiplying(byPowerOf10: 8)
                .int64Value
            memo += ":\(amountInSmallestUnit)"
        }
        return memo
    }

    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", nodeAddress)
        dict.set("newAddress", newAddress)
        if rebondAmount > 0 {
            dict.set("rebondAmount", "\(rebondAmount)")
        }
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
            amount: amount.formatToDecimal(digits: coin.decimals),
            memo: toString(),
            gas: gas,
            transactionType: .unspecified,
            memoFunctionDictionary: toDictionary().allItems()
        )
    }
}

struct ReBondFormView: View {
    @Bindable var model: FunctionCallReBond
    let coin: Coin

    var body: some View {
        VStack {
            AddressTextField(
                address: $model.nodeAddress,
                label: "nodeAddress".localized,
                coin: coin,
                error: $model.nodeAddressError
            ) { result in
                model.handle(nodeAddressResult: result)
            }

            AddressTextField(
                address: $model.newAddress,
                label: "newAddress".localized,
                coin: coin,
                error: $model.newAddressError
            ) { result in
                model.handle(newAddressResult: result)
            }

            StyledFloatingPointField(
                label: "rebondAmount".localized,
                placeholder: "rebondAmountPlaceholder".localized,
                value: $model.rebondAmount,
                isValid: .constant(true),
                isOptional: true
            )

            Text("rebondNote".localized)
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal)

            if let errorMessage = model.customErrorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
        .onAppear {
            model.validate(against: coin)
        }
    }
}
