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

    let sendInteractor: SendInteractor = DefaultSendInteractor.live

    var availableAmount: Decimal {
        usdcCoin?.balanceDecimal ?? 0
    }

    var coinMeta: CoinMeta? {
        usdcCoin?.toCoinMeta()
    }

    init(vault: Vault) {
        self.vault = vault
        fetchUsdcCoin()
    }

    func onLoad() async {
        isLoading = true
        defer { isLoading = false }

        guard let usdcCoin else { return }
        await BalanceService.shared.updateBalance(for: usdcCoin)

        setupForm()
        amountField.validators.append(AmountBalanceValidator(balance: usdcCoin.balanceDecimal))
    }

    func fetchUsdcCoin() {
        let (chain, _) = CircleViewLogic.getChainDetails()
        guard let coin = vault.coins.first(where: { $0.chain == chain && $0.ticker == "USDC" }) else {
            return
        }

        usdcCoin = coin
    }

    func makeTransaction() async -> SendTransaction? {
        guard let coin = usdcCoin,
              let toAddress = vault.circleWalletAddress else {
            return nil
        }

        isLoading = true
        defer { isLoading = false }

        let isFast = vault.fastVaultEligibility
        return SendTransaction.empty(coin: coin, vault: vault).with(
            toAddress: toAddress,
            amount: amountField.value,
            isFastVault: isFast
        )
    }
}
