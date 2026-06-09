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
    /// it before letting the user delegate up to "max". This is what backs
    /// the `AmountBalanceValidator` and the "Max" path, so `amount + fee`
    /// can never exceed the spendable balance.
    var stakeableBalance: Decimal {
        let remaining = coin.balanceDecimal - feeDecimal
        return remaining > 0 ? remaining : 0
    }

    /// Network fee for a single `MsgDelegate` in human-decimal coin units.
    /// For delegate, both the staked amount AND this fee draw on the liquid
    /// (spendable) balance.
    var feeDecimal: Decimal {
        guard let entry = try? CosmosStakingConfig.entry(for: coin.chain) else {
            return 0
        }
        let divisor = pow(Decimal(10), coin.decimals)
        return Decimal(entry.feeAmount) / divisor
    }

    /// Insufficient-fee pre-flight. When the spendable balance is below the
    /// fee, `stakeableBalance` collapses to 0 and the amount validator would
    /// reject every input with a misleading "amount exceeded"; this gates the
    /// builder and drives a clear inline fee message instead.
    var hasSufficientBalanceForFee: Bool {
        coin.balanceDecimal >= feeDecimal
    }

    var transactionBuilder: TransactionBuilder? {
        validateErrors()
        guard validForm, hasSufficientBalanceForFee, let validator = selectedValidator else { return nil }
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
