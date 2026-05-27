//
//  CosmosDelegateTransactionViewModel.swift
//  VultisigApp
//
//  Form view-model for the LUNA / LUNC delegate flow. Same `Form` +
//  `[FormField]` + `transactionBuilder` shape as `BondTransactionViewModel`
//  and `StakeTransactionViewModel` — view holds only `@FocusState` and
//  cosmetic state, every business field lives here.
//

import Foundation
import Combine

@MainActor
final class CosmosDelegateTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault

    @Published var validForm: Bool = false
    @Published var selectedValidator: CosmosValidator?

    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0",
        validators: [
            RequiredValidator(errorMessage: "emptyAmountField".localized)
        ]
    )

    private(set) var isMaxAmount: Bool = false
    private(set) lazy var form: [FormField] = [amountField]

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    init(coin: Coin, vault: Vault) {
        self.coin = coin
        self.vault = vault
    }

    func onLoad() {
        setupForm()
        amountField.validators.append(AmountBalanceValidator(balance: stakeableBalance))
    }

    /// Headroom-aware stakeable balance — the cosmos fee for a single
    /// `MsgDelegate` lives in the same denom as the bond, so we must reserve
    /// it before letting the user delegate up to "max".
    var stakeableBalance: Decimal {
        let total = coin.balanceDecimal
        let reserved = feeReservation
        let remaining = total - reserved
        return remaining > 0 ? remaining : 0
    }

    private var feeReservation: Decimal {
        guard let entry = try? CosmosStakingConfig.entry(for: coin.chain) else {
            return 0
        }
        let divisor = pow(Decimal(10), coin.decimals)
        return Decimal(entry.feeAmount) / divisor
    }

    var transactionBuilder: TransactionBuilder? {
        validateErrors()
        guard validForm, let validator = selectedValidator else { return nil }
        guard !validator.jailed else { return nil }
        return CosmosDelegateTransactionBuilder(
            coin: coin,
            amount: amountField.value.formatToDecimal(digits: coin.decimals),
            sendMaxAmount: isMaxAmount,
            validatorAddress: validator.operatorAddress
        )
    }

    func onPercentage(_ percentage: Double) {
        isMaxAmount = percentage == 100
    }
}
