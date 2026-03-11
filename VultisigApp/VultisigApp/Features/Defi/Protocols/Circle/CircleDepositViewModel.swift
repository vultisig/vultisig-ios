//
//  CircleDepositViewModel.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-13.
//

import Foundation
import Combine

@MainActor
final class CircleDepositViewModel: ObservableObject, Form {
    let vault: Vault

    @Published var validForm: Bool = false
    @Published var isLoading = false
    @Published private(set) var usdcCoin: Coin?
    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0",
        validators: [RequiredValidator(errorMessage: "emptyAmountField".localized)]
    )

    private(set) lazy var form: [FormField] = [amountField]
    var formCancellable: AnyCancellable?

    let tx = SendTransaction()
    let sendCryptoViewModel = SendCryptoViewModel()

    var availableAmount: Decimal {
        usdcCoin?.balanceDecimal ?? 0
    }

    var coinMeta: CoinMeta? {
        usdcCoin?.toCoinMeta()
    }

    init(vault: Vault) {
        self.vault = vault
    }

    func onLoad() async {
        isLoading = true
        defer { isLoading = false }

        let (chain, _) = CircleViewLogic.getChainDetails()

        guard let coin = vault.coins.first(where: { $0.chain == chain && $0.ticker == "USDC" }) else {
            return
        }

        await BalanceService.shared.updateBalance(for: coin)

        usdcCoin = coin
        tx.reset(coin: coin)

        setupForm()
        amountField.validators.append(AmountBalanceValidator(balance: coin.balanceDecimal))

        await sendCryptoViewModel.loadFastVault(tx: tx, vault: vault)
    }

    func onContinue() async {
        guard let coin = usdcCoin,
              let toAddress = vault.circleWalletAddress else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        tx.coin = coin
        tx.fromAddress = coin.address
        tx.toAddress = toAddress
        tx.amount = amountField.value

        await sendCryptoViewModel.loadFastVault(tx: tx, vault: vault)
    }
}
