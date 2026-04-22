//
//  UnstakeTransactionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation
import Combine

final class UnstakeTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault
    let isAutocompound: Bool
    let availableToUnstake: Decimal?

    @Published var percentageSelected: Double? = 100
    @Published var availableAmount: Decimal = 0
    var autocompoundBalance: Decimal = 0
    @Published var validForm: Bool = false
    @Published var amountField = FormField(label: "amount".localized)

    private(set) var isMaxAmount: Bool = false
    private(set) lazy var form: [FormField] = [
        amountField
    ]

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    init(coin: Coin, vault: Vault, isAutocompound: Bool, availableToUnstake: Decimal? = nil) {
        self.coin = coin
        self.vault = vault
        self.isAutocompound = isAutocompound
        self.availableToUnstake = availableToUnstake
    }

    func onLoad() {
        setupForm()
        availableAmount = availableToUnstake ?? coin.stakedBalanceDecimal
        setupAmountField()

        if isAutocompound {
            Task { @MainActor in
                await fetchAutocompoundBalance()
                self.availableAmount = autocompoundBalance
                self.setupAmountField()
            }
        }
    }

    var transactionBuilder: TransactionBuilder? {
        validateErrors()
        guard validForm else { return nil }

        switch coin.ticker.uppercased() {
        case "TCY":
            return TCYUnstakeTransactionBuilder(
                coin: coin,
                percentage: Int(percentageSelected ?? percentageFromAmount),
                autoCompoundAmount: autocompoundBalance,
                sendMaxAmount: isMaxAmount,
                isAutoCompound: isAutocompound
            )
        case "RUJI":
            return RUJIUnstakeTransactionBuilder(
                coin: coin,
                amount: amountField.value,
                sendMaxAmount: isMaxAmount
            )

        case "CACAO":
            return CacaoUnstakeTransactionBuilder(
                coin: coin,
                bps: Int(percentageSelected ?? percentageFromAmount) * 100,
            )
        default:
            return nil
        }
    }

    var percentageFromAmount: Double {
        guard availableAmount != .zero else { return 0 }
        let decimal = (amountField.value.toDecimal() / availableAmount) * 100.0
        return (decimal as NSDecimalNumber).doubleValue
    }

    func onPercentage(_ percentage: Double) {
        isMaxAmount = percentage == 100
    }

    func setupAmountField() {
        self.amountField.validators = [
            AmountBalanceValidator(balance: self.availableAmount)
        ]
        self.percentageSelected = 100
        self.isMaxAmount = true
    }

    func fetchAutocompoundBalance() async {
        switch coin.ticker.uppercased() {
        case "TCY":
            let amount = await ThorchainService.shared.fetchTcyAutoCompoundAmount(address: coin.address)
            self.autocompoundBalance = coin.valueWithDecimals(value: amount)
        default:
            break
        }
    }
}
