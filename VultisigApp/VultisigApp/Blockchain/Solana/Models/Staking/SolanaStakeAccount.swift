//
//  SolanaStakeAccount.swift
//  VultisigApp
//
//  Parsed Solana stake account — the read-side model the staking UI binds to
//  (delegation amount, validator, activation state, withdraw authority). One
//  stake account delegates to exactly one validator; a wallet can hold N.
//
//  Decoded from a `getAccountInfo` / `getProgramAccounts` `jsonParsed` row
//  (`value.data.parsed.info.{meta,stake}`). The on-chain numbers
//  (`activationEpoch`, `deactivationEpoch`, `stake`, `rentExemptReserve`) are
//  serialized as decimal STRINGS in jsonParsed — they're u64 and exceed JSON's
//  safe-integer range — so the wire model keeps them as strings and the public
//  model converts to `UInt64`.
//

import Foundation

/// Activation lifecycle of a stake delegation, derived from the account's
/// `activationEpoch` / `deactivationEpoch` relative to the current epoch.
/// Solana stake activates at the next epoch boundary and cools down ~1 epoch
/// after a deactivate before the funds can be withdrawn.
enum SolanaStakeActivationState: String, Codable, Hashable {
    /// Delegated this epoch — warming up, not yet fully effective.
    case activating
    /// Fully delegated and earning rewards.
    case active
    /// Deactivate submitted — cooling down this epoch, not yet withdrawable.
    case deactivating
    /// No active delegation — either never delegated or fully cooled down.
    case inactive
}

struct SolanaStakeAccount: Codable, Hashable, Identifiable {
    /// Stake account address (its own pubkey, not the owner's).
    let pubkey: String
    /// The account's total lamports (delegated stake + rent reserve + any
    /// undelegated lamports).
    let lamports: UInt64
    /// Rent-exempt reserve held by the account — not part of the delegated /
    /// withdrawable stake.
    let rentExemptReserve: UInt64
    /// Authority allowed to delegate / deactivate the stake.
    let staker: String
    /// Authority allowed to withdraw the stake.
    let withdrawer: String
    /// The delegation, or `nil` for an initialized-but-undelegated account
    /// (`parsed.type == "initialized"`, no `stake.delegation`).
    let delegation: Delegation?

    var id: String { pubkey }

    struct Delegation: Codable, Hashable {
        /// Vote account this stake is delegated to.
        let votePubkey: String
        /// Epoch the delegation began activating.
        let activationEpoch: UInt64
        /// Epoch the delegation began deactivating, or `UInt64.max` while
        /// active (the Stake program's "not deactivating" sentinel).
        let deactivationEpoch: UInt64
        /// Delegated lamports.
        let stake: UInt64

        /// `true` when no deactivation has been scheduled.
        var isDeactivationSentinel: Bool {
            deactivationEpoch == SolanaStakingConfig.epochSentinel
        }
    }

    /// Derives the lifecycle state from the current epoch. Pure so the cooldown
    /// gate and the UI share one definition.
    ///
    /// - activating: delegation began this epoch and is not deactivating.
    /// - deactivating: a deactivation was scheduled and the current epoch has
    ///   not yet passed it.
    /// - active: delegated in a prior epoch and not deactivating.
    /// - inactive: no delegation, or the deactivation epoch has passed.
    func activationState(currentEpoch: UInt64) -> SolanaStakeActivationState {
        guard let delegation else { return .inactive }

        if !delegation.isDeactivationSentinel {
            // A deactivation is scheduled. Still cooling down until the current
            // epoch passes the deactivation epoch; inactive afterwards.
            return currentEpoch <= delegation.deactivationEpoch ? .deactivating : .inactive
        }

        // No deactivation scheduled — activating in its first epoch, active after.
        return currentEpoch <= delegation.activationEpoch ? .activating : .active
    }
}

// MARK: - jsonParsed wire decoding

/// Mirrors the `jsonParsed` Stake-program account shape so the parsed-info tree
/// decodes straight off the RPC envelope. `init(from:)` on `SolanaStakeAccount`
/// folds this wire tree into the flat public model, converting the u64 string
/// fields to `UInt64`.
extension SolanaStakeAccount {

    /// Builds the model from a decoded `getProgramAccounts` row
    /// (`{ pubkey, account }`). Returns `nil` when the account is not a parsed
    /// stake account (e.g. a `dataSlice`d pubkey-only row, or a non-stake
    /// program account) — callers fetch full `jsonParsed` info separately for
    /// those.
    init?(programAccount: SolanaStakeProgramAccount) {
        guard let parsed = programAccount.account.data.parsed else { return nil }
        self.init(pubkey: programAccount.pubkey, lamports: programAccount.account.lamports, parsed: parsed)
    }

    private init?(pubkey: String, lamports: UInt64, parsed: SolanaStakeParsed) {
        let info = parsed.info
        guard let rentReserve = UInt64(info.meta.rentExemptReserve) else { return nil }

        var delegation: Delegation?
        if let stake = info.stake {
            let d = stake.delegation
            guard
                let activation = UInt64(d.activationEpoch),
                let deactivation = UInt64(d.deactivationEpoch),
                let stakeLamports = UInt64(d.stake)
            else { return nil }
            delegation = Delegation(
                votePubkey: d.voter,
                activationEpoch: activation,
                deactivationEpoch: deactivation,
                stake: stakeLamports
            )
        }

        self.pubkey = pubkey
        self.lamports = lamports
        self.rentExemptReserve = rentReserve
        self.staker = info.meta.authorized.staker
        self.withdrawer = info.meta.authorized.withdrawer
        self.delegation = delegation
    }
}

// MARK: - jsonParsed wire types

/// A `getProgramAccounts` result row for the Stake program.
struct SolanaStakeProgramAccount: Decodable {
    let pubkey: String
    let account: Account

    struct Account: Decodable {
        let lamports: UInt64
        let data: SolanaStakeAccountData
    }
}

/// The `value` of a `getAccountInfo` result for a Stake-program account.
struct SolanaStakeAccountInfoValue: Decodable {
    let lamports: UInt64
    let data: SolanaStakeAccountData
}

/// `account.data` in jsonParsed form. `parsed` is absent when the data was
/// requested as base64 / dataSliced rather than jsonParsed.
struct SolanaStakeAccountData: Decodable {
    let parsed: SolanaStakeParsed?
}

struct SolanaStakeParsed: Decodable {
    /// `"delegated"`, `"initialized"`, etc. Kept for future copy; not required
    /// for parsing since `stake` presence already discriminates delegation.
    let type: String?
    let info: Info

    struct Info: Decodable {
        let meta: Meta
        let stake: Stake?

        struct Meta: Decodable {
            let rentExemptReserve: String
            let authorized: Authorized

            struct Authorized: Decodable {
                let staker: String
                let withdrawer: String
            }
        }

        struct Stake: Decodable {
            let delegation: Delegation

            struct Delegation: Decodable {
                let voter: String
                let stake: String
                let activationEpoch: String
                let deactivationEpoch: String
            }
        }
    }
}
