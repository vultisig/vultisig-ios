//
//  SolanaDelegateTransactionViewModel.swift
//  VultisigApp
//
//  Form view-model for the Solana delegate flow. Same `Form` + `[FormField]` +
//  `transactionBuilder` shape as `CosmosDelegateTransactionViewModel` — the
//  view holds only `@FocusState` and cosmetic state, every business field
//  lives here.
//
//  Stakeable balance reserves BOTH the network fee AND the rent-exempt reserve
//  the new stake account must hold, so `amount + fee + rentReserve` can never
//  exceed the spendable balance.
//

import Foundation
import Combine
import OSLog

@MainActor
final class SolanaDelegateTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault

    @Published var validForm: Bool = false
    @Published var selectedValidator: SolanaValidator?
    // Seeded with the deterministic size-200 stake-account reserve so the
    // "fund entered + rent" math is correct even before the live
    // getMinimumBalanceForRentExemption read returns; overwritten on load.
    @Published private(set) var rentReserve: Decimal =
        Decimal(SolanaStakingConfig.rentExemptReserveLamports) / Decimal(SolanaStakingConfig.lamportsPerSol)

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

    private let stakingService: SolanaStakingServiceProtocol
    private let logger = Logger(
        subsystem: "com.vultisig.app",
        category: "solana-delegate-vm"
    )

    init(
        coin: Coin,
        vault: Vault,
        stakingService: SolanaStakingServiceProtocol = SolanaStakingService.shared
    ) {
        self.coin = coin
        self.vault = vault
        self.stakingService = stakingService
    }

    func onLoad() {
        setupForm()
        refreshAmountValidators()
        Task { await loadRentReserve() }
    }

    /// (Re)builds the amount-field validators against the CURRENT
    /// `stakeableBalance`. Called again after `loadRentReserve()` because the live
    /// rent reserve can exceed the seeded estimate, shrinking `stakeableBalance` —
    /// without a rebuild the balance guard would keep validating against the stale
    /// snapshot and let an amount through that no longer fits (and overfund the
    /// stake account).
    private func refreshAmountValidators() {
        amountField.validators = [
            RequiredValidator(errorMessage: "emptyAmountField".localized),
            AmountBalanceValidator(balance: stakeableBalance),
            // Minimum-delegation guard. The user enters the amount they want
            // ACTIVELY staked; the Solana mainnet minimum delegation is 1 SOL
            // (getStakeMinimumDelegation), enforced by the Stake program — a
            // DelegateStake below it reverts with StakeError.InsufficientDelegation
            // (custom error 12). The rent-exempt reserve is added on top
            // automatically in `transactionBuilder`, so the user only needs to
            // enter >= 1 SOL.
            ClosureValidator { [weak self] value in
                guard let self else { return }
                guard value.toDecimal() >= self.minimumDelegationDecimal else {
                    throw SolanaDelegateValidationError.belowMinimum(self.minimumDelegationDecimal)
                }
            }
        ]
    }

    /// Minimum amount the user may enter — the 1 SOL program minimum delegation.
    /// This is the ACTIVE stake; the rent reserve is funded on top separately, so
    /// the user is not asked to do the "1 SOL + rent" math.
    var minimumDelegationDecimal: Decimal {
        Decimal(SolanaStakingConfig.minDelegationFloorLamports) / pow(Decimal(10), coin.decimals)
    }

    private func loadRentReserve() async {
        do {
            let reserveLamports = try await stakingService.fetchRentReserve()
            let divisor = pow(Decimal(10), coin.decimals)
            rentReserve = Decimal(reserveLamports) / divisor
            // Rebuild the balance guard against the now-live `stakeableBalance`; if
            // the user already entered an amount that no longer fits, re-validate
            // immediately so the form rejects it.
            refreshAmountValidators()
            if amountField.touched {
                validateErrors()
                validForm = form.allSatisfy { $0.valid }
            }
        } catch {
            logger.error("Rent reserve fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Headroom-aware stakeable balance — reserves the network fee AND the
    /// rent-exempt reserve the new stake account must hold, both drawn from the
    /// liquid SOL balance, before letting the user delegate up to "max".
    var stakeableBalance: Decimal {
        let remaining = coin.balanceDecimal - feeDecimal - rentReserve
        return remaining > 0 ? remaining : 0
    }

    /// Network fee for a delegate tx in human-decimal SOL. The delegate builds
    /// create + initialize + delegate in one transaction; the base lamport fee
    /// plus the priority fee is the same flat fee the transfer path uses.
    var feeDecimal: Decimal {
        let divisor = pow(Decimal(10), coin.decimals)
        return Decimal(string: SolanaHelper.defaultFeeInLamports.description).map { $0 / divisor } ?? 0
    }

    /// Insufficient-funds pre-flight. When the spendable balance can't cover the
    /// fee + rent reserve, `stakeableBalance` collapses to 0 and the amount
    /// validator would reject every input with a misleading "amount exceeded";
    /// this gates the builder and drives a clear inline message instead.
    var hasSufficientBalanceForFee: Bool {
        coin.balanceDecimal >= feeDecimal + rentReserve
    }

    var transactionBuilder: TransactionBuilder? {
        validateErrors()
        guard validForm, hasSufficientBalanceForFee, let validator = selectedValidator else { return nil }
        // The user enters the amount to ACTIVELY stake; a new stake account must
        // additionally hold the rent-exempt reserve (active stake = funding −
        // rent). Fund with entered + rent so the delegated stake equals what the
        // user typed and clears the 1 SOL minimum. The headroom-aware
        // `stakeableBalance` already reserves both fee and rent, so this can't
        // overdraw.
        let funding = amountField.value.toDecimal() + rentReserve
        return SolanaDelegateTransactionBuilder(
            coin: coin,
            amount: NSDecimalNumber(decimal: funding).stringValue,
            sendMaxAmount: isMaxAmount,
            votePubkey: validator.votePubkey
        )
    }

    func onPercentage(_ percentage: Double) {
        isMaxAmount = percentage == 100
    }
}

enum SolanaDelegateValidationError: LocalizedError {
    case belowMinimum(Decimal)

    var errorDescription: String? {
        switch self {
        case .belowMinimum(let minimum):
            let handler = NSDecimalNumberHandler(
                roundingMode: .up, scale: 4,
                raiseOnExactness: false, raiseOnOverflow: false,
                raiseOnUnderflow: false, raiseOnDivideByZero: false
            )
            let formatted = NSDecimalNumber(decimal: minimum)
                .rounding(accordingToBehavior: handler).stringValue
            return String(format: "solanaStakingMinimumDelegation".localized, formatted)
        }
    }
}
