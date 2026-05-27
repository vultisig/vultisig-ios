//
//  CosmosUndelegateTransactionViewModel.swift
//  VultisigApp
//
//  Form view-model for the LUNA / LUNC undelegate flow. The validator is
//  pre-selected by the caller (always launched from a position card on
//  the DeFi tab); there's no validator picker. Amount is bounded by the
//  currently-staked balance at that validator.
//

import Foundation
import Combine

@MainActor
final class CosmosUndelegateTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault
    /// Operator-bech32 of the source validator. Comes from the position
    /// card; surfaced on the screen for the user to confirm.
    let validatorAddress: String
    let validatorMoniker: String
    /// Currently-staked amount at the validator (human decimal). Caps the
    /// `amountField` validator — undelegating more than staked is rejected
    /// by the chain post-broadcast, so we fail closed at form-validate time.
    let stakedBalance: Decimal

    @Published var validForm: Bool = false

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

    init(
        coin: Coin,
        vault: Vault,
        validatorAddress: String,
        validatorMoniker: String,
        stakedBalance: Decimal
    ) {
        self.coin = coin
        self.vault = vault
        self.validatorAddress = validatorAddress
        self.validatorMoniker = validatorMoniker
        self.stakedBalance = stakedBalance
    }

    func onLoad() {
        setupForm()
        amountField.validators.append(AmountBalanceValidator(balance: stakedBalance))
        amountField.value = stakedBalance.formatToDecimal(digits: coin.decimals)
        isMaxAmount = true
    }

    var transactionBuilder: TransactionBuilder? {
        validateErrors()
        guard validForm else { return nil }
        return CosmosUndelegateTransactionBuilder(
            coin: coin,
            amount: amountField.value.formatToDecimal(digits: coin.decimals),
            sendMaxAmount: isMaxAmount,
            validatorAddress: validatorAddress
        )
    }

    /// 21-day unbonding-lock notice copy — surfaced on the verify screen
    /// so the user knows their funds are locked. Returns the formatted
    /// unlock date computed from the chain's `unbondingDays`.
    var unbondingLockMessage: String? {
        guard let days = try? CosmosStakingConfig.unbondingDays(for: coin.chain) else {
            return nil
        }
        let unlockDate = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return String(
            format: "cosmosStakingUnbondingLockNotice".localized,
            days,
            formatter.string(from: unlockDate)
        )
    }

    func onPercentage(_ percentage: Double) {
        isMaxAmount = percentage == 100
    }
}
