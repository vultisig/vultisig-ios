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
    /// Pool chosen via the picker (first-time stake only). `nil` until the user
    /// selects one. Add-more reuses `existingPoolAddress` instead.
    @Published var selectedPool: TonStakingPool?

    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0",
        validators: [RequiredValidator(errorMessage: "emptyAmountField".localized)]
    )

    private(set) var isMaxAmount: Bool = false
    private(set) lazy var form: [FormField] = [amountField]

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    /// Conservative fallback floor (TON) for the minimum stake before a pool is
    /// picked (or for add-more, where the pool isn't re-fetched). Real pools
    /// require far more; this only guards against dust stakes.
    static let defaultMinStake: Decimal = 1

    /// Minimum stake (human-decimal TON) the amount must clear: the selected
    /// pool's `min_stake` once picked, otherwise the conservative floor.
    var minStake: Decimal {
        selectedPool?.minStake ?? Self.defaultMinStake
    }

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
                    throw MinStakeError.belowMinimum(self.minStake, self.coin.chain.ticker)
                }
            }
        )
    }

    /// The destination pool for the stake transaction. Reuses the existing pool
    /// for add-more, otherwise the picked pool's address.
    var destinationPoolAddress: String? {
        existingPoolAddress ?? selectedPool?.address
    }

    /// Whether a destination pool has been resolved (existing or picked).
    var hasDestinationPool: Bool {
        destinationPoolAddress != nil
    }

    var transactionBuilder: TransactionBuilder? {
        validateErrors()
        guard validForm, hasSufficientBalanceForFee, let poolAddress = destinationPoolAddress else {
            return nil
        }
        return TonStakeTransactionBuilder(
            coin: coin,
            amount: amountField.value.formatToDecimal(digits: coin.decimals),
            poolAddress: poolAddress
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
