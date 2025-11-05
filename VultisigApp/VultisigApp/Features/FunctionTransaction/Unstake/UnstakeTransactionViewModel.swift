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
    
    var supportsAutocompound: Bool {
        coin.supportsAutocompound
    }
    
    @Published var percentageSelected: Int? = 100
    @Published var availableAmount: Decimal = 0
    var autocompoundBalance: Decimal = 0
    @Published var isAutocompound: Bool = false
    @Published var validForm: Bool = false
    @Published var amountField = FormField(label: "amount".localized)
    
    private(set) var isMaxAmount: Bool = false
    private(set) lazy var form: [FormField] = [
        amountField
    ]
    
    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()
    
    init(coin: Coin, vault: Vault) {
        self.coin = coin
        self.vault = vault
    }
    
    func onLoad() {
        setupForm()
        availableAmount = coin.stakedBalanceDecimal
        setupAmountField()
        
        $isAutocompound
            .receive(on: DispatchQueue.main)
            .sink(weak: self) { viewModel, isAutoCompound in
                viewModel.updateAvailableBalance()
            }
            .store(in: &cancellables)
    }
    
    var transactionBuilder: TransactionBuilder? {
        guard validForm else { return nil }
        
        switch coin.ticker.uppercased() {
        case "TCY":
            return TCYUnstakeTransactionBuilder(
                coin: coin,
                percentage: percentageSelected ?? percentageFromAmount,
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
        default:
            return nil
        }
    }
    
    var percentageFromAmount: Int {
        let decimal = (amountField.value.toDecimal() / availableAmount) * 100.0
        let intValue = Int((decimal as NSDecimalNumber).doubleValue)
        return intValue
    }
    
    func onPercentage(_ percentage: Int) {
        isMaxAmount = percentage == 100
    }
    
    func updateAvailableBalance() {
        Task { @MainActor in
            if autocompoundBalance == .zero {
                await fetchAutocompoundBalance()
            }
            
            self.availableAmount = isAutocompound ? autocompoundBalance : coin.stakedBalanceDecimal
            self.setupAmountField()
        }
    }
    
    func setupAmountField() {
        self.amountField.validators = [
            AmountBalanceValidator(balance: self.availableAmount)
        ]
        self.percentageSelected = 100
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
