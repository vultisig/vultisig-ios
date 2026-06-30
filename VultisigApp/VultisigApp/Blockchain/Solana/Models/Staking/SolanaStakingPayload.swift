//
//  SolanaStakingPayload.swift
//  VultisigApp
//
//  Carries the Solana staking-operation intent from the build-keysign step into
//  the signing layer (wallet-core's Solana stake proto: delegate / deactivate /
//  withdraw). Analog: `CosmosStakingPayload`.
//
//  Discriminated by `opType`. Field set per op:
//    .delegate  → votePubkey, lamports
//    .unstake   → stakeAccount            (deactivate; no amount)
//    .withdraw  → stakeAccount, lamports
//

import Foundation

enum SolanaStakingOpType: String, Codable, Hashable {
    case delegate
    case unstake
    case withdraw
}

struct SolanaStakingPayload: Codable, Hashable {
    let opType: SolanaStakingOpType
    /// Vote account to delegate to (`.delegate`).
    let votePubkey: String?
    /// Source stake account for `.unstake` / `.withdraw`.
    let stakeAccount: String?
    /// Lamports for `.delegate` / `.withdraw`. `nil` for `.unstake` (deactivate
    /// carries no amount — the whole account cools down).
    let lamports: UInt64?

    static func delegate(votePubkey: String, lamports: UInt64) -> SolanaStakingPayload {
        SolanaStakingPayload(
            opType: .delegate,
            votePubkey: votePubkey,
            stakeAccount: nil,
            lamports: lamports
        )
    }

    static func unstake(stakeAccount: String) -> SolanaStakingPayload {
        SolanaStakingPayload(
            opType: .unstake,
            votePubkey: nil,
            stakeAccount: stakeAccount,
            lamports: nil
        )
    }

    static func withdraw(stakeAccount: String, lamports: UInt64) -> SolanaStakingPayload {
        SolanaStakingPayload(
            opType: .withdraw,
            votePubkey: nil,
            stakeAccount: stakeAccount,
            lamports: lamports
        )
    }
}
