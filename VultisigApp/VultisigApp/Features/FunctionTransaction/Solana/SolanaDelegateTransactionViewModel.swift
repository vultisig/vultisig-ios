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
    @Published private(set) var rentReserve: Decimal = 0

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
        stakingService: SolanaStakingServiceProtocol = SolanaStakingService()
    ) {
        self.coin = coin
        self.vault = vault
        self.stakingService = stakingService
    }

    func onLoad() {
        setupForm()
        amountField.validators.append(AmountBalanceValidator(balance: stakeableBalance))
        // Minimum-delegation guard: the Solana mainnet minimum delegation is
        // 1 SOL (getStakeMinimumDelegation), enforced by the Stake program —
        // a DelegateStake below it reverts with StakeError.InsufficientDelegation
        // (custom error 12). The active stake = funding − rent reserve, so the
        // funding floor is 1 SOL + rent. Read `minimumDelegationDecimal` live so
        // it picks up the rent reserve once it loads.
        amountField.validators.append(ClosureValidator { [weak self] value in
            guard let self else { return }
            guard value.toDecimal() >= self.minimumDelegationDecimal else {
                throw SolanaDelegateValidationError.belowMinimum(self.minimumDelegationDecimal)
            }
        })
        Task { await loadRentReserve() }
    }

    /// Funding floor for a new stake account: the 1 SOL program minimum
    /// delegation plus the rent-exempt reserve (active stake = funding − rent).
    var minimumDelegationDecimal: Decimal {
        let oneSol = Decimal(SolanaStakingConfig.minDelegationFloorLamports) / pow(Decimal(10), coin.decimals)
        return oneSol + rentReserve
    }

    private func loadRentReserve() async {
        do {
            let reserveLamports = try await stakingService.fetchRentReserve()
            let divisor = pow(Decimal(10), coin.decimals)
            rentReserve = Decimal(reserveLamports) / divisor
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
        return SolanaDelegateTransactionBuilder(
            coin: coin,
            amount: amountField.value.formatToDecimal(digits: coin.decimals),
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
