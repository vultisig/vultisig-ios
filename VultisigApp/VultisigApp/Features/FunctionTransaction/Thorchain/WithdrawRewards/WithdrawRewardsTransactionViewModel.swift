//
//  WithdrawRewardsTransactionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation
import Combine

final class WithdrawRewardsTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault
    let rewards: Decimal
    let rewardsCoin: CoinMeta

    @Published var percentageSelected: Double? = 100
    @Published var validForm: Bool = false
    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0"
    )

    private(set) var isMaxAmount: Bool = false
    private(set) lazy var form: [FormField] = [
        amountField
    ]

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    init(
        coin: Coin,
        vault: Vault,
        rewards: Decimal,
        rewardsCoin: CoinMeta
    ) {
        self.coin = coin
        self.vault = vault
        self.rewards = rewards
        self.rewardsCoin = rewardsCoin
    }

    func onLoad() {
        setupForm()
        amountField.validators = [
            AmountBalanceValidator(balance: rewards)
        ]
        amountField.value = rewards.formatForDisplay(maxDecimals: rewardsCoin.decimals)
        percentageSelected = 100
    }

    var transactionBuilder: TransactionBuilder? {
        validateErrors()
        guard validForm else { return nil }
        return RUJIWithdrawRewardsTransactionBuilder(
            coin: coin,
            withdrawAmount: amountField.value,
            sendMaxAmount: isMaxAmount
        )
    }

    func onPercentage(_ percentage: Double) {
        isMaxAmount = percentage == 100
    }
}
