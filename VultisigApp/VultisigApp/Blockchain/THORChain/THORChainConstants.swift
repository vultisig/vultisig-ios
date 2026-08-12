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

    /// 60 / blockTimeSeconds. Whole, so minutes ↔ blocks is exact in both
    /// directions and a duration picker offering minutes never has to round.
    static let blocksPerMinute = 60 / blockTimeSeconds

    /// Convert wall-clock minutes to a THORChain block count. Exact, because
    /// `blocksPerMinute` is a whole number.
    static func blocks(forMinutes minutes: Int) -> Int {
        minutes * blocksPerMinute
    }

    /// Exact inverse of `blocks(forMinutes:)` for any block count this app
    /// produces — the duration picker's finest grain is one minute, and a minute
    /// is a whole number of blocks.
    static func minutes(forBlocks blocks: Int) -> Int {
        blocks / blocksPerMinute
    }

    /// Fallback ceiling for a resting limit order's TTL, in blocks.
    ///
    /// THORChain caps the `=<` memo's interval field at the `StreamingLimitSwapMaxAge`
    /// mimir and applies the cap **silently** — a larger interval is overwritten
    /// with the max, not rejected — so a client that offers a longer expiry would
    /// be promising a window the chain never grants. The live value is fetched
    /// (`LimitSwapQuoteServiceProtocol.fetchStreamingLimitSwapMaxAge`); this is
    /// the documented default used when that fetch fails, and it is also the
    /// value mainnet currently runs: 43,200 blocks ≈ 3 days at 6s.
    static let defaultLimitSwapMaxAgeBlocks = 43_200

    /// Floor the app imposes on a custom expiry. **Not a protocol rule** — the
    /// chain validates only the ceiling, and an interval of 1 block is accepted.
    ///
    /// It exists because a very short order cannot realistically fill, and
    /// closing it is not free: the deposit costs an inbound network fee and the
    /// refund costs an outbound one. 10 minutes is short enough to be useful for
    /// a fast trade and long enough that the order gets a real chance.
    ///
    /// Note this is NOT about waiting for the deposit to confirm: the TTL clock
    /// starts when the order enters the queue (THORNode sets `InitialBlockHeight`
    /// at that point), which is already after observation and confirmation
    /// counting — so a slow source chain does not eat into the window, and the
    /// floor does not need to vary per chain.
    static let minLimitSwapAgeBlocks = 100

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
