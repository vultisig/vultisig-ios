//
//  SolanaWithdrawTransactionViewModel.swift
//  VultisigApp
//
//  Form view-model for the Solana withdraw flow. The stake account is
//  pre-selected by the caller. Withdraw moves the full withdrawable balance
//  (delegated stake + auto-compounded rewards, minus the rent-exempt reserve)
//  back to the wallet — there's no amount field and no rewards-claim op.
//
//  The Continue CTA is DISABLED until the account is fully inactive: on load
//  the VM reads the live epoch and runs `SolanaEpochCooldownGate`. While the
//  account is still cooling down, the CTA stays disabled and a "available to
//  withdraw in N epochs (~M days)" notice is shown.
//

import Foundation
import Combine
import OSLog

@MainActor
final class SolanaWithdrawTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault
    /// Stake account being withdrawn from. Surfaced read-only for confirmation.
    let stakeAccount: SolanaStakeAccount

    @Published var validForm: Bool = true
    /// Cooldown gate state, evaluated against the live epoch on load. `nil`
    /// until the first epoch read completes — the CTA stays disabled until then.
    @Published private(set) var cooldownState: SolanaEpochCooldownState?
    /// Live network epoch from the last read; drives the remaining-epochs copy.
    @Published private(set) var currentEpoch: UInt64?

    private(set) lazy var form: [FormField] = []

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    private let stakingService: SolanaStakingServiceProtocol
    private let logger = Logger(
        subsystem: "com.vultisig.app",
        category: "solana-withdraw-vm"
    )

    init(
        coin: Coin,
        vault: Vault,
        stakeAccount: SolanaStakeAccount,
        stakingService: SolanaStakingServiceProtocol = SolanaStakingService.shared
    ) {
        self.coin = coin
        self.vault = vault
        self.stakeAccount = stakeAccount
        self.stakingService = stakingService
    }

    func onLoad() {
        setupForm()
        Task { await evaluateCooldown() }
    }

    private func evaluateCooldown() async {
        do {
            let epochInfo = try await stakingService.fetchEpochInfo()
            currentEpoch = epochInfo.epoch
            cooldownState = SolanaEpochCooldownGate.evaluate(
                stakeAccount: stakeAccount,
                currentEpoch: epochInfo.epoch
            )
        } catch {
            logger.error("Epoch info fetch failed: \(error.localizedDescription, privacy: .public)")
            // Fail closed — leave the gate unresolved so the CTA stays disabled
            // rather than letting a withdraw through on a still-cooling account.
            currentEpoch = nil
            cooldownState = nil
        }
    }

    /// `true` once the live epoch has advanced past the account's deactivation
    /// epoch (or the account was never deactivating). Drives the CTA enablement.
    var isWithdrawable: Bool {
        cooldownState == .available
    }

    /// Full withdrawable lamports — the account's total lamports minus its
    /// rent-exempt reserve. After full inactivity the delegated stake plus any
    /// auto-compounded rewards are all withdrawable; the reserve must remain to
    /// keep the account rent-exempt until it's closed.
    var withdrawableLamports: UInt64 {
        stakeAccount.lamports >= stakeAccount.rentExemptReserve
            ? stakeAccount.lamports - stakeAccount.rentExemptReserve
            : 0
    }

    /// Human-decimal withdrawable amount, for display and the builder.
    var withdrawableAmount: Decimal {
        let divisor = pow(Decimal(10), coin.decimals)
        return Decimal(withdrawableLamports) / divisor
    }

    var feeDecimal: Decimal {
        let divisor = pow(Decimal(10), coin.decimals)
        return Decimal(string: SolanaHelper.defaultFeeInLamports.description).map { $0 / divisor } ?? 0
    }

    var hasSufficientBalanceForFee: Bool {
        coin.balanceDecimal >= feeDecimal
    }

    /// Cooldown notice copy while the account is still deactivating —
    /// "available to withdraw in N epochs (~M days)". `nil` once withdrawable.
    var cooldownMessage: String? {
        guard case .blocked(let unlocksAtEpoch)? = cooldownState else { return nil }
        let epochsRemaining = remainingEpochs(unlocksAtEpoch: unlocksAtEpoch)
        let days = SolanaStakingCooldownEstimate.approximateDays(epochs: epochsRemaining)
        return String(format: "solanaStakingWithdrawCooldownNotice".localized, epochsRemaining, days)
    }

    /// Epochs until the account unlocks, from the live epoch. Clamped to ≥ 1 so
    /// the copy never reads "0 epochs" while the gate still blocks (the gate and
    /// this share the same live epoch, so a 0 here would contradict `.blocked`).
    private func remainingEpochs(unlocksAtEpoch: UInt64) -> Int {
        guard let currentEpoch, unlocksAtEpoch > currentEpoch else { return 1 }
        let remaining = unlocksAtEpoch - currentEpoch
        return Int(min(remaining, UInt64(Int.max)))
    }

    var transactionBuilder: TransactionBuilder? {
        guard isWithdrawable, hasSufficientBalanceForFee, withdrawableLamports > 0 else { return nil }
        return SolanaWithdrawTransactionBuilder(
            coin: coin,
            stakeAccount: stakeAccount.pubkey,
            amount: withdrawableAmount.formatToDecimal(digits: coin.decimals)
        )
    }
}
