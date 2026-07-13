//
//  StakeTransactionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation
import Combine

final class StakeTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault
    let isAutocompound: Bool

    @Published var validForm: Bool = false
    @Published private(set) var stakedAmount: Decimal = 0
    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0",
        validators: [RequiredValidator(errorMessage: "emptyAmountField".localized)]
    )

    private(set) var isMaxAmount: Bool = false
    private(set) lazy var form: [FormField] = [
        amountField
    ]

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    private let mayaAPIService = MayaChainAPIService()

    /// Maximum stakeable amount (accounting for gas fees for CACAO)
    var maxStakeableAmount: Decimal {
        if coin.ticker.uppercased() == "CACAO" {
            return mayaAPIService.getStakeableCacaoAmount(walletBalance: coin.balanceDecimal)
        }
        return coin.balanceDecimal
    }

    init(coin: Coin, vault: Vault, isAutocompound: Bool) {
        self.coin = coin
        self.vault = vault
        self.isAutocompound = isAutocompound
    }

    func onLoad() {
        setupForm()
        amountField.validators.append(AmountBalanceValidator(balance: coin.balanceDecimal))
    }

    var transactionBuilder: TransactionBuilder? {
        validateErrors()
        guard validForm else { return nil }

        switch coin.ticker.uppercased() {
        case "TCY":
            return TCYStakeTransactionBuilder(
                coin: coin,
                amount: amountField.value,
                sendMaxAmount: isMaxAmount,
                isAutoCompound: isAutocompound
            )
        case "BRUNE":
            return BRUNEStakeTransactionBuilder(
                coin: coin,
                amount: amountField.value,
                sendMaxAmount: isMaxAmount
            )
        case "RUJI":
            return RUJIStakeTransactionBuilder(
                coin: coin,
                amount: amountField.value,
                sendMaxAmount: isMaxAmount
            )
        case "CACAO":
            return CacaoStakeTransactionBuilder(
                coin: coin,
                amount: amountField.value
            )
        default:
            return nil
        }
    }

    func onPercentage(_ percentage: Double) {
        isMaxAmount = percentage == 100
    }
}
