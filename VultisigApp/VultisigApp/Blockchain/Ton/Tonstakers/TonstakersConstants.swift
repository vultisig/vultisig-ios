//
//  TonstakersConstants.swift
//  VultisigApp
//

import Foundation
import BigInt

/// Canonical mainnet Tonstakers (TON liquid-staking, `liquidTF`) addresses and
/// parameters. Verified 2026-06-25 against tonapi `/v2/staking/pool/{pool}`:
/// the pool reports `implementation:"liquidTF"`, `min_stake: 1e9`, and the
/// `liquid_jetton_master` below; live deposits to the pool carry op
/// `0x47d54391`.
enum TonstakersConstants {
    /// Pool contract (deposit target). Raw `workchain:hex` form.
    static let poolAddress = "0:a45b17f28409229b78360e3290420f13e4fe20f90d7e2bf8c4ac6703259e22fa"

    /// tsTON jetton master (`liquid_jetton_master`). Raw form. Used to read the
    /// user's tsTON balance and resolve their tsTON jetton wallet for the burn.
    static let tsTONMasterAddress = "0:bdf3fa8098d129b54b4f73b5bac5d1e1fd91eb054169c3916dfc8ccd536d1000"

    /// tsTON has 9 decimals (same as TON), per the jetton master metadata.
    static let tsTONDecimals = 9

    /// CoinGecko / price-provider id for tsTON.
    static let tsTONPriceProviderId = "tonstakers-staked-ton"

    /// Minimum deposit enforced by the pool: 1 TON.
    static let minStakeNano: BigInt = BigInt(1_000_000_000)

    /// TON attached to a deposit message for gas on top of the staked amount is
    /// NOT separate — the staked TON itself is the message value. The pool keeps
    /// the principal and refunds excess gas. For the BURN message (which carries
    /// no TON principal, only the tsTON jetton being burned), we attach this TON
    /// for forward gas so the pool can process the withdrawal and return change.
    static let burnGasNano: BigInt = BigInt(100_000_000) // 0.1 TON
}
