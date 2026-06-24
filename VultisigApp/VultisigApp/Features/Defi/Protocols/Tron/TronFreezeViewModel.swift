//
//  TronFreezeViewModel.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import Foundation
import Combine
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "tron-freeze-view-model")

@MainActor
final class TronFreezeViewModel: ObservableObject, Form {
    let vault: Vault

    @Published var selectedResourceType: TronResourceType = .bandwidth
    @Published var percentageSelected: Double?
    @Published var availableBalance: Decimal = .zero
    @Published var validForm: Bool = false
    @Published var error: Error?
    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0",
        validators: [RequiredValidator(errorMessage: "emptyAmountField".localized)]
    )

    private(set) lazy var form: [FormField] = [amountField]

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    var trxCoin: Coin? {
        TronViewLogic.getTrxCoin(vault: vault)
    }

    init(vault: Vault) {
        self.vault = vault
    }

    func onLoad() {
        setupForm()
        amountField.validators.append(AmountBalanceValidator(balance: availableBalance))
    }

    func loadBalance() async {
        guard let coin = trxCoin else {
            await MainActor.run { self.error = TronStakingError.noTrxCoin }
            return
        }

        await BalanceService.shared.updateBalance(for: coin)

        await MainActor.run {
            self.availableBalance = coin.balanceDecimal
            self.amountField.validators = [
                RequiredValidator(errorMessage: "emptyAmountField".localized),
                AmountBalanceValidator(balance: coin.balanceDecimal)
            ]
        }
    }

    /// Builds the TRON freeze transaction. Preserves the memo format
    /// (`FREEZE:<RESOURCE>`), the staking flag, and send-to-self that
    /// `TronHelper` consumes.
    func makeTransaction() -> SendTransaction? {
        validateErrors()
        guard validForm, let coin = trxCoin else { return nil }

        let amountDecimal = amountField.value.toDecimal()
        guard amountDecimal > 0 else { return nil }

        let memo = "FREEZE:\(selectedResourceType.tronResourceString)"

        // Drop the cached account/resource for this address so balances
        // refresh when the user navigates back into the DeFi screens after
        // the freeze is broadcast.
        let address = coin.address
        Task { await TronService.shared.invalidateAccountCache(for: address) }

        return SendTransaction.empty(coin: coin, vault: vault).with(
            toAddress: coin.address,
            amount: amountDecimal.description,
            memo: memo,
            isStakingOperation: true
        )
    }
}
