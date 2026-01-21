//
//  BondTransactionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation
import Combine

final class BondTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault
    let initialBondAddress: String?

    @Published var validForm: Bool = false

    @Published var addressViewModel: AddressViewModel
    @Published var providerViewModel: AddressViewModel
    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0 RUNE",
        validators: [
            RequiredValidator(errorMessage: "emptyAmountField".localized)
        ]
    )
    @Published var operatorFeeField = FormField(
        label: "operatorFeesLabel".localized,
        placeholder: "0"
    )

    private(set) var isMaxAmount: Bool = false
    private(set) lazy var form: [FormField] = [
        addressViewModel.field,
        providerViewModel.field,
        amountField,
        operatorFeeField
    ]

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    init(coin: Coin, vault: Vault, initialBondAddress: String?) {
        self.coin = coin
        self.vault = vault
        self.initialBondAddress = initialBondAddress
        self.addressViewModel = AddressViewModel(
            coin: coin,
            additionalValidators: [RequiredValidator(errorMessage: "emptyAddressField".localized)]
        )
        self.providerViewModel = AddressViewModel(label: "providerLabel".localized, coin: coin)
    }

    func onLoad() {
        setupForm()
        operatorFeeField.validators = [
            ClosureValidator { value in
                if value.isEmpty && self.providerViewModel.field.value.isNotEmpty {
                    throw HelperError.runtimeError("operatorFeesError".localized)
                }

                if !value.isEmpty && Int64(value) == nil {
                    throw HelperError.runtimeError("invalidOperatorFee".localized)
                }
            }
        ]

        amountField.validators.append(AmountBalanceValidator(balance: coin.balanceDecimal))

        if let initialBondAddress {
            addressViewModel.field.value = initialBondAddress
        }
    }

    var transactionBuilder: TransactionBuilder? {
        validateErrors()
        guard validForm else { return nil }

        return BondTransactionBuilder(
            coin: coin,
            amount: amountField.value.formatToDecimal(digits: coin.decimals),
            sendMaxAmount: isMaxAmount,
            nodeAddress: addressViewModel.field.value,
            providerAddress: providerViewModel.field.value,
            operatorFee: Int64(operatorFeeField.value)
        )
    }

    func onPercentage(_ percentage: Double) {
        isMaxAmount = percentage == 100
    }
}
