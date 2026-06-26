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

import Foundation

enum SolanaStakingOpType: String, Codable, Hashable {
    case delegate
    case unstake
    case withdraw
    case moveStakeStep
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

    static func delegate(votePubkey: String, lamports: UInt64) -> SolanaStakingPayload {
        SolanaStakingPayload(
            opType: .delegate,
            votePubkey: votePubkey,
            stakeAccount: nil,
            destinationStakeAccount: nil,
            lamports: lamports
        )
    }

    static func unstake(stakeAccount: String) -> SolanaStakingPayload {
        SolanaStakingPayload(
            opType: .unstake,
            votePubkey: nil,
            stakeAccount: stakeAccount,
            destinationStakeAccount: nil,
            lamports: nil
        )
    }

    static func withdraw(stakeAccount: String, lamports: UInt64) -> SolanaStakingPayload {
        SolanaStakingPayload(
            opType: .withdraw,
            votePubkey: nil,
            stakeAccount: stakeAccount,
            destinationStakeAccount: nil,
            lamports: lamports
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
            lamports: lamports
        )
    }
}
