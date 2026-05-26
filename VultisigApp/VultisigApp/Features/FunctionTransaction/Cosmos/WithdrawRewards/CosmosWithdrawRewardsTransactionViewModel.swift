//
//  CosmosWithdrawRewardsTransactionViewModel.swift
//  VultisigApp
//
//  Claim-rewards flow VM for LUNA / LUNC. Selection-driven — no
//  `FormField` for the amount because the per-validator pending reward
//  is what's claimed (the user picks *which* validators, not *how much*).
//
//  Three load-bearing rules per the spec risk register:
//  - Multi-validator batch is signed in ONE MPC ceremony via a single
//    multi-msg TxBody (D-2).
//  - Soft UI cap of 8 validators per batch (D-9) — beyond 8 the gas
//    budget on LUNC (8 × 1.5M = 12M units → 800M uluna) becomes
//    user-hostile, and the cap forces a "split into multiple claims" UX.
//  - Balance pre-flight (Risk 3): `coin.balance >= feeAmount × N`. Fail
//    closed at form-validate time so the user never burns MPC on an
//    insufficient-fees rejection.
//

import Foundation
import Combine

@MainActor
final class CosmosWithdrawRewardsTransactionViewModel: ObservableObject {
    /// Soft UI cap per Spec Decision 9. The proto encoder is unbounded —
    /// this is purely an ergonomic guardrail driven by the LUNC gas math.
    static let maxBatchSize: Int = 8

    let coin: Coin
    let vault: Vault
    let candidates: [CosmosWithdrawRewardsCandidate]

    @Published var selectedValidators: Set<String>
    @Published var hitBatchCapWarning: Bool = false

    init(
        coin: Coin,
        vault: Vault,
        candidates: [CosmosWithdrawRewardsCandidate]
    ) {
        self.coin = coin
        self.vault = vault
        self.candidates = candidates
        // Default-select all but cap at the soft batch size so the user
        // doesn't accidentally over-select when opening the sheet.
        let preselected = candidates
            .prefix(Self.maxBatchSize)
            .map(\.validatorAddress)
        self.selectedValidators = Set(preselected)
        self.hitBatchCapWarning = candidates.count > Self.maxBatchSize
    }

    var totalSelectedReward: Decimal {
        candidates
            .filter { selectedValidators.contains($0.validatorAddress) }
            .map(\.pendingReward)
            .reduce(0, +)
    }

    /// Estimated fee in human-decimal coin units. Scales linearly with the
    /// selected validator count, matching the SignDoc resolver's batch
    /// gas/fee multiplier.
    var estimatedFee: Decimal {
        guard let entry = try? CosmosStakingConfig.entry(for: coin.chain) else {
            return 0
        }
        let perMsg = Decimal(entry.feeAmount)
        let count = Decimal(max(selectedValidators.count, 1))
        let divisor = pow(Decimal(10), coin.decimals)
        return (perMsg * count) / divisor
    }

    /// Insufficient-balance pre-flight per Spec Risk 3. Compares total
    /// estimated fee against the spendable coin balance.
    var hasSufficientBalanceForFee: Bool {
        coin.balanceDecimal >= estimatedFee
    }

    /// Form is valid only when:
    ///  - at least one validator is selected
    ///  - selection does not exceed the soft cap
    ///  - the fee pre-flight clears
    var validForm: Bool {
        guard !selectedValidators.isEmpty else { return false }
        guard selectedValidators.count <= Self.maxBatchSize else { return false }
        guard hasSufficientBalanceForFee else { return false }
        return true
    }

    func toggle(validator: CosmosWithdrawRewardsCandidate) {
        if selectedValidators.contains(validator.validatorAddress) {
            selectedValidators.remove(validator.validatorAddress)
            hitBatchCapWarning = false
        } else {
            guard selectedValidators.count < Self.maxBatchSize else {
                hitBatchCapWarning = true
                return
            }
            selectedValidators.insert(validator.validatorAddress)
        }
    }

    func toggleSelectAll() {
        if selectedValidators.count == min(candidates.count, Self.maxBatchSize) {
            selectedValidators.removeAll()
            hitBatchCapWarning = false
        } else {
            let target = candidates
                .prefix(Self.maxBatchSize)
                .map(\.validatorAddress)
            selectedValidators = Set(target)
            hitBatchCapWarning = candidates.count > Self.maxBatchSize
        }
    }

    var transactionBuilder: TransactionBuilder? {
        guard validForm else { return nil }
        // Preserve the order in which candidates were returned by the
        // LCD — important for byte-equality vs. the SDK reference.
        let orderedValidators = candidates
            .map(\.validatorAddress)
            .filter { selectedValidators.contains($0) }
        return CosmosWithdrawRewardsTransactionBuilder(
            coin: coin,
            validatorAddresses: orderedValidators
        )
    }
}
