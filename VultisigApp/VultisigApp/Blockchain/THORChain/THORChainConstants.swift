//
//  THORChainConstants.swift
//  VultisigApp
//

import Foundation

enum THORChainConstants {
    /// Average THORChain block time in seconds. Constant since launch.
    static let blockTimeSeconds = 6

    /// 3600 / blockTimeSeconds.
    static let blocksPerHour = 3600 / blockTimeSeconds

    /// Convert wall-clock hours to a THORChain block count.
    static func blocks(forHours hours: Int) -> Int {
        hours * blocksPerHour
    }

    /// Convert a THORChain block count back to wall-clock hours — the inverse of
    /// `blocks(forHours:)`. A placed limit order encodes its expiry as whole
    /// hours × `blocksPerHour`, so a co-signer that only has the memo can recover
    /// the original hours by dividing. Integer division floors any block count
    /// that isn't an exact multiple, which never happens for orders this app
    /// builds but keeps the reverse mapping total.
    static func hours(forBlocks blocks: Int) -> Int {
        blocks / blocksPerHour
    }

    /// Gas the signer stamps on every THORChain `MsgDeposit`, in RUNE base
    /// units (1e8). Charged against the account rather than taken out of the
    /// deposited coins.
    ///
    /// Named here rather than left as a literal in the signer so a screen that
    /// needs to pre-flight "can this account afford the deposit at all?" checks
    /// against the SAME number that gets signed, instead of inventing a second
    /// one that can drift out of agreement with it.
    /// `UInt64` to match WalletCore's `CosmosFee.gas` field exactly — a signed
    /// type here would need a cast at the signing site, which is where a wrong
    /// number would be least visible.
    static let depositGasBaseUnits: UInt64 = 20_000_000
}
