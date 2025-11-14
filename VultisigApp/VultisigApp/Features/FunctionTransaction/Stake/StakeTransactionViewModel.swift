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
    let defaultAutocompound: Bool
    
    var supportsAutocompound: Bool {
        coin.supportsAutocompound
    }
    
    @Published var isAutocompound: Bool = false
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
    
    init(coin: Coin, vault: Vault, defaultAutocompound: Bool) {
        self.coin = coin
        self.vault = vault
        self.defaultAutocompound = defaultAutocompound
    }
    
    func onLoad() {
        setupForm()
        amountField.validators.append(AmountBalanceValidator(balance: coin.balanceDecimal))
        isAutocompound = defaultAutocompound
    }
    
    var transactionBuilder: TransactionBuilder? {
        guard validForm else { return nil }
        
        switch coin.ticker.uppercased() {
        case "TCY":
            return TCYStakeTransactionBuilder(
                coin: coin,
                amount: amountField.value,
                sendMaxAmount: isMaxAmount,
                isAutoCompound: isAutocompound
            )
        case "RUJI":
            return RUJIStakeTransactionBuilder(
                coin: coin,
                amount: amountField.value,
                sendMaxAmount: isMaxAmount
            )
        default:
            return nil
        }
    }
    
    func onPercentage(_ percentage: Double) {
        isMaxAmount = percentage == 100
    }
}
