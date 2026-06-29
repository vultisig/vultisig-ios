//
//  SolanaStakingPayload.swift
//  VultisigApp
//
//  Carries the Solana staking-operation intent from a future build-keysign
//  step into the signing layer (wallet-core's Solana stake proto:
//  delegate / deactivate / withdraw / move-stake). Data-only here — no signing
//  is wired in this PR. Analog: `CosmosStakingPayload`.
//
//  Discriminated by `opType`. Field set per op:
//    .delegate       → votePubkey, lamports
//    .unstake        → stakeAccount            (deactivate; no amount)
//    .withdraw       → stakeAccount, lamports
//    .moveStakeStep  → stakeAccount, destinationStakeAccount, votePubkey, lamports
//
//  A move-stake (redelegate A → B) is a guided, multi-transaction, cross-epoch
//  flow — Solana has no native redelegate. It decomposes into discrete
//  sub-steps via `moveStakeSubStep`, each mapping to a distinct keysign:
//    .split       → carve the chosen amount into a fresh split account (partial
//                   moves only; a whole-account move skips this).
//    .deactivate  → DeactivateStake on the moved account; begins the ~1-epoch
//                   cooldown. Byte-identical to a plain unstake.
//    .redelegate  → DelegateStake the now-inactive moved account to validator B
//                   (the explicit `stakeAccount` field targets the existing
//                   account rather than deriving a new one).
//

import Foundation

enum SolanaStakingOpType: String, Codable, Hashable {
    case delegate
    case unstake
    case withdraw
    case moveStakeStep
}

/// One discrete keysign within the guided move-stake flow. The flow is
/// multi-transaction and spans epochs, so each sub-step is signed and broadcast
/// independently; the next becomes available only once the chain reflects the
/// previous (inferred from the parsed stake state, so it is resumable).
enum SolanaMoveStakeStep: String, Codable, Hashable {
    /// Carve `lamports` off the source account into the pinned split account
    /// (`destinationStakeAccount`). Partial moves only — whole-account moves
    /// skip straight to `.deactivate`.
    case split
    /// Deactivate the moved account, starting its ~1-epoch cooldown.
    case deactivate
    /// Re-delegate the now-inactive moved account to validator B (`votePubkey`).
    case redelegate
}

struct SolanaStakingPayload: Codable, Hashable {
    let opType: SolanaStakingOpType
    /// Vote account to delegate to (`.delegate`) or the move-stake destination's
    /// delegation target (`.moveStakeStep`).
    let votePubkey: String?
    /// Source stake account for `.unstake` / `.withdraw` / `.moveStakeStep`.
    let stakeAccount: String?
    /// Destination stake account for a `.moveStakeStep`.
    let destinationStakeAccount: String?
    /// Lamports for `.delegate` / `.withdraw` / `.moveStakeStep`. `nil` for
    /// `.unstake` (deactivate carries no amount — the whole account cools down).
    let lamports: UInt64?
    /// The active sub-step of a guided move-stake flow. `nil` for non-move ops
    /// and for the legacy whole-payload `moveStakeStep` factory.
    let moveStakeSubStep: SolanaMoveStakeStep?

    static func delegate(votePubkey: String, lamports: UInt64) -> SolanaStakingPayload {
        SolanaStakingPayload(
            opType: .delegate,
            votePubkey: votePubkey,
            stakeAccount: nil,
            destinationStakeAccount: nil,
            lamports: lamports,
            moveStakeSubStep: nil
        )
    }

    static func unstake(stakeAccount: String) -> SolanaStakingPayload {
        SolanaStakingPayload(
            opType: .unstake,
            votePubkey: nil,
            stakeAccount: stakeAccount,
            destinationStakeAccount: nil,
            lamports: nil,
            moveStakeSubStep: nil
        )
    }

    static func withdraw(stakeAccount: String, lamports: UInt64) -> SolanaStakingPayload {
        SolanaStakingPayload(
            opType: .withdraw,
            votePubkey: nil,
            stakeAccount: stakeAccount,
            destinationStakeAccount: nil,
            lamports: lamports,
            moveStakeSubStep: nil
        )
    }

    static func moveStakeStep(
        stakeAccount: String,
        destinationStakeAccount: String,
        votePubkey: String,
        lamports: UInt64
    ) -> SolanaStakingPayload {
        SolanaStakingPayload(
            opType: .moveStakeStep,
            votePubkey: votePubkey,
            stakeAccount: stakeAccount,
            destinationStakeAccount: destinationStakeAccount,
            lamports: lamports,
            moveStakeSubStep: nil
        )
    }

    /// `.split` sub-step — carve `lamports` off `stakeAccount` into the pinned
    /// `destinationStakeAccount`. Partial moves only.
    static func moveStakeSplit(
        sourceStakeAccount: String,
        splitStakeAccount: String,
        votePubkey: String,
        lamports: UInt64
    ) -> SolanaStakingPayload {
        SolanaStakingPayload(
            opType: .moveStakeStep,
            votePubkey: votePubkey,
            stakeAccount: sourceStakeAccount,
            destinationStakeAccount: splitStakeAccount,
            lamports: lamports,
            moveStakeSubStep: .split
        )
    }

    /// `.deactivate` sub-step — deactivate the moved account, starting cooldown.
    static func moveStakeDeactivate(
        movedStakeAccount: String,
        votePubkey: String
    ) -> SolanaStakingPayload {
        SolanaStakingPayload(
            opType: .moveStakeStep,
            votePubkey: votePubkey,
            stakeAccount: movedStakeAccount,
            destinationStakeAccount: nil,
            lamports: nil,
            moveStakeSubStep: .deactivate
        )
    }

    /// `.redelegate` sub-step — delegate the now-inactive moved account to B.
    static func moveStakeRedelegate(
        movedStakeAccount: String,
        votePubkey: String,
        lamports: UInt64
    ) -> SolanaStakingPayload {
        SolanaStakingPayload(
            opType: .moveStakeStep,
            votePubkey: votePubkey,
            stakeAccount: movedStakeAccount,
            destinationStakeAccount: nil,
            lamports: lamports,
            moveStakeSubStep: .redelegate
        )
    }
}
