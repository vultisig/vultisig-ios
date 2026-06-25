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
    /// Implementation of the existing pool (`whales`, `tf`, …), used to resolve
    /// the deposit comment for add-more. `nil` for a first-time stake, where the
    /// picked pool's implementation is used instead.
    let existingPoolImplementation: String?

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

    /// TON nominator pools deduct a ~1 TON processing commission on deposit, so
    /// the sent amount must clear the pool minimum PLUS this buffer — depositing
    /// exactly `min_stake` is rejected by the pool contract (which, sent
    /// bounceable, returns the funds rather than crediting a position).
    static let depositFeeBuffer: Decimal = 1

    /// Pool minimum (human-decimal TON): the selected pool's `min_stake` once
    /// picked, otherwise the conservative floor.
    var minStake: Decimal {
        selectedPool?.minStake ?? Self.defaultMinStake
    }

    /// Effective minimum the amount must clear: the pool minimum plus the
    /// deposit-processing buffer.
    var requiredMinStake: Decimal {
        minStake + Self.depositFeeBuffer
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

    init(coin: Coin, vault: Vault, existingPoolAddress: String?, existingPoolImplementation: String? = nil) {
        self.coin = coin
        self.vault = vault
        self.existingPoolAddress = existingPoolAddress
        self.existingPoolImplementation = existingPoolImplementation
    }

    func onLoad() {
        setupForm()
        amountField.validators.append(AmountBalanceValidator(balance: maxStakeableAmount))
        amountField.validators.append(
            ClosureValidator { [weak self] value in
                guard let self else { return }
                let amount = value.toDecimal()
                if amount < self.requiredMinStake {
                    throw MinStakeError.belowMinimum(self.requiredMinStake, self.coin.chain.ticker)
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

    /// Implementation of the destination pool: the existing pool's for add-more,
    /// otherwise the picked pool's. Resolves the deposit comment.
    var destinationPoolImplementation: String? {
        isFirstTimeStake ? selectedPool?.implementation : existingPoolImplementation
    }

    /// Deposit text comment for the destination pool, resolved from its
    /// implementation (`whales` → "Stake", `tf` → "d"). `nil` for an
    /// unsupported/unknown implementation — the build is blocked rather than
    /// sending a guessed comment that the pool contract would reject.
    var depositComment: String? {
        TonStakingComment.deposit(for: destinationPoolImplementation)
    }

    var transactionBuilder: TransactionBuilder? {
        validateErrors()
        guard validForm,
              hasSufficientBalanceForFee,
              let poolAddress = destinationPoolAddress,
              let memo = depositComment else {
            return nil
        }
        return TonStakeTransactionBuilder(
            coin: coin,
            amount: amountField.value.formatToDecimal(digits: coin.decimals),
            poolAddress: poolAddress,
            memo: memo
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
