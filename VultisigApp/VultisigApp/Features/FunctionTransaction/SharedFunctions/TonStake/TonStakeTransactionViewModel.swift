//
//  TonStakeTransactionViewModel.swift
//  VultisigApp
//

import Foundation
import Combine
import BigInt

@MainActor
final class TonStakeTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault

    /// Existing pool the user is adding more stake to. `nil` for a first-time
    /// stake — the screen then exposes the validated pool-address field.
    let existingPoolAddress: String?

    @Published var validForm: Bool = false
    @Published var poolAddress: String = ""
    @Published var poolAddressError: String?

    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0",
        validators: [RequiredValidator(errorMessage: "emptyAmountField".localized)]
    )

    /// Pool minimum stake (human-decimal TON), fetched from tonapi when the
    /// destination pool is known. Stake amount must clear this plus the network
    /// fee. Defaults to a conservative floor until/if the pool reports its own.
    @Published private(set) var minStake: Decimal = TonStakeTransactionViewModel.defaultMinStake

    private(set) var isMaxAmount: Bool = false
    private(set) lazy var form: [FormField] = [amountField]

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    private let service = TonService.shared

    /// Conservative fallback floor (TON) for the minimum stake when the pool's
    /// own `min_stake` is unavailable. Real nominator pools require far more
    /// (tens of TON); this only guards against dust stakes.
    static let defaultMinStake: Decimal = 1

    var isFirstTimeStake: Bool { existingPoolAddress == nil }

    /// Network fee (TON `defaultFee`, in nanotons) reserved from the spendable
    /// balance, scaled to human-decimal TON.
    var feeDecimal: Decimal {
        TonHelper.defaultFee.description.toDecimal() / pow(Decimal(10), coin.decimals)
    }

    /// Max stakeable amount, reserving the network fee.
    var maxStakeableAmount: Decimal {
        let remaining = coin.balanceDecimal - feeDecimal
        return remaining > 0 ? remaining : 0
    }

    var hasSufficientBalanceForFee: Bool {
        coin.balanceDecimal > feeDecimal
    }

    init(coin: Coin, vault: Vault, existingPoolAddress: String?) {
        self.coin = coin
        self.vault = vault
        self.existingPoolAddress = existingPoolAddress
    }

    func onLoad() {
        setupForm()
        amountField.validators.append(AmountBalanceValidator(balance: maxStakeableAmount))
        amountField.validators.append(
            ClosureValidator { [weak self] value in
                guard let self else { return }
                let amount = value.toDecimal()
                if amount < self.minStake {
                    throw MinStakeError.belowMinimum(self.minStake, self.coin.ticker)
                }
            }
        )
        if let existingPoolAddress {
            poolAddress = existingPoolAddress
            Task { await loadMinStake(for: existingPoolAddress) }
        }
    }

    /// The destination pool for the stake transaction. Reuses the existing
    /// pool for add-more, otherwise the validated typed address.
    var destinationPoolAddress: String {
        existingPoolAddress ?? poolAddress.trimmingCharacters(in: .whitespaces)
    }

    var isPoolAddressValid: Bool {
        FunctionCallAddressValidation.isValidThorMayaTON(destinationPoolAddress)
    }

    func validatePoolAddress() {
        poolAddressError = FunctionCallAddressValidation.errorForThorMayaTON(poolAddress)
        if isFirstTimeStake, isPoolAddressValid {
            Task { await loadMinStake(for: destinationPoolAddress) }
        }
    }

    private func loadMinStake(for poolAddress: String) async {
        guard let info = await service.getStakingPoolInfo(poolAddress: poolAddress),
              let rawMin = info.minStake else {
            return
        }
        minStake = Decimal(rawMin) / pow(Decimal(10), coin.decimals)
    }

    var transactionBuilder: TransactionBuilder? {
        validateErrors()
        guard validForm, hasSufficientBalanceForFee, isPoolAddressValid else { return nil }
        return TonStakeTransactionBuilder(
            coin: coin,
            amount: amountField.value.formatToDecimal(digits: coin.decimals),
            poolAddress: destinationPoolAddress
        )
    }

    func onPercentage(_ percentage: Double) {
        isMaxAmount = percentage == 100
    }
}

enum MinStakeError: LocalizedError {
    case belowMinimum(Decimal, String)

    var errorDescription: String? {
        switch self {
        case let .belowMinimum(minimum, ticker):
            return String(format: "tonStakeBelowMinimum".localized, minimum.formatForDisplay(), ticker)
        }
    }
}
