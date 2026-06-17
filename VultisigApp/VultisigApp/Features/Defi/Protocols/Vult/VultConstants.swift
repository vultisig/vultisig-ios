//
//  VultConstants.swift
//  VultisigApp
//

import Foundation
import BigInt

/// Single source of truth for the VULT staking wrapper (`sVULT`).
///
/// `sVULT` is an OpenZeppelin `ERC20Wrapper` (+ `ERC20Votes` + `ERC20Permit`):
/// it wraps VULT 1:1 into a governance/staking token. Two addresses must never be
/// confused:
/// - `stakedVult` is the wrapper and the target of every user transaction
///   (`depositFor` / `requestUnstake` / `claim` / `cancelUnstake`).
/// - `underlyingVult` is the ERC-20 being staked (the `approve` token). Read
///   `underlying()` on-chain to confirm it rather than trusting this constant
///   blindly.
enum VultConstants {
    /// The sVULT staking wrapper. Target of all user txs and the `approve` spender.
    static let stakedVult = "0x11113d7311FB8584a6e82BB126aA11D92e5fB39B"

    /// Underlying VULT ERC-20 (18 decimals). Confirm via `underlying()` at runtime.
    static let underlyingVult = "0xb788144DF611029C60b859DF47e79B7726C4DEBa"

    static let chain: Chain = .ethereum

    /// VULT and sVULT share 18 decimals (1:1 wrap).
    static let assetDecimals = 18

    /// Tickers shown in the UI. The staked balance reads as sVULT but is priced and
    /// labelled to the user as VULT (1:1) per product copy.
    static let underlyingTicker = "VULT"
    static let sharesTicker = "sVULT"

    /// `priceProviderId` for the VULT rate (CoinGecko id). Pricing uses VULT, never
    /// USDC.
    static let priceProviderId = "vultisig"

    /// Fallback cooldown used only if the live `cooldownDuration()` read fails. The
    /// contract's current cooldown is 2 days; the live value is authoritative.
    static let fallbackCooldownSeconds: BigInt = 2 * 24 * 60 * 60

    /// Function selectors (keccak256(signature)[0..4]), verified against the
    /// Sourcify-published ABI for `0x11113d73…`.
    enum Selector {
        /// `depositFor(address account, uint256 value)` — stake.
        static let depositFor = "2f4f21e2"
        /// `requestUnstake(uint256 amount)` — burns active sVULT into escrow.
        static let requestUnstake = "23095721"
        /// `claim(uint256 requestId, address receiver)` — collect after maturity.
        static let claim = "ddd5e1b2"
        /// `cancelUnstake(uint256 requestId)` — restore escrowed sVULT.
        static let cancelUnstake = "2b187b2b"
        /// `balanceOf(address)` — active staked sVULT (1:1 VULT).
        static let balanceOf = "70a08231"
        /// `cooldownDuration()` — current unstake cooldown in seconds.
        static let cooldownDuration = "35269315"
        /// `getUnstakeRequest(uint256)` → `(address owner, uint256 maturity, uint256 amount)`.
        static let getUnstakeRequest = "ddb59e13"
        /// `isClaimable(uint256)` → bool.
        static let isClaimable = "89610a09"
        /// `underlying()` → the staked ERC-20 address.
        static let underlying = "6f307dc3"
    }

    /// Event topic0 hashes (keccak256(eventSignature)), verified against the ABI.
    enum EventTopic {
        /// `UnstakeRequested(address indexed owner, uint256 indexed requestId, uint256 amount, uint256 maturity)`.
        static let unstakeRequested = "0x6930caaa0f0843978bf16992d58b9fd54913ce2e45b8acdd34f5b44f95419db2"
    }
}
