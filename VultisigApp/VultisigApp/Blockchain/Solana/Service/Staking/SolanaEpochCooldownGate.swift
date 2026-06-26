//
//  SolanaEpochCooldownGate.swift
//  VultisigApp
//
//  Gates a stake-account withdraw on the deactivation cooldown. After a
//  deactivate, the stake cools down for ~1 epoch: the lamports become
//  withdrawable only once the network epoch has advanced PAST the account's
//  `deactivationEpoch`. Evaluating this before a (future) withdraw keysign
//  avoids surprising the user with a transaction the Stake program would
//  reject. Analog: `CosmosRedelegationCooldownGate`.
//

import Foundation

enum SolanaEpochCooldownState: Equatable {
    /// Stake is fully cooled down (or was never deactivating) — withdraw is
    /// allowed.
    case available
    /// Still cooling down — withdraw unlocks at `unlocksAtEpoch`.
    case blocked(unlocksAtEpoch: UInt64)
}

enum SolanaEpochCooldownGate {
    /// Evaluates whether `stakeAccount`'s deactivated stake can be withdrawn at
    /// `currentEpoch`. Pure function over the parsed delegation + the live
    /// epoch so the unit tests can pin the boundary deterministically.
    ///
    /// - A non-deactivating account (sentinel `deactivationEpoch`) is `available`
    ///   — there is nothing cooling down. (Whether it's still *delegated* is a
    ///   separate concern handled by the delegate/unstake flows.)
    /// - A deactivating account unlocks once the network advances past its
    ///   deactivation epoch, i.e. at `deactivationEpoch + 1`.
    static func evaluate(
        stakeAccount: SolanaStakeAccount,
        currentEpoch: UInt64
    ) -> SolanaEpochCooldownState {
        guard let delegation = stakeAccount.delegation else {
            return .available
        }
        if delegation.isDeactivationSentinel {
            return .available
        }
        if currentEpoch > delegation.deactivationEpoch {
            return .available
        }
        // `deactivationEpoch` is < .max here (not the sentinel), so +1 is safe.
        return .blocked(unlocksAtEpoch: delegation.deactivationEpoch + 1)
    }
}
