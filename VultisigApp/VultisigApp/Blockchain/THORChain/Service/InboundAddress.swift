//
//  InboundAddress.swift
//  VultisigApp
//
//  Created by Johnny Luo on 17/4/2025.
//

/*
 {
 "chain": "GAIA",
 "pub_key": "thorpub1addwnpepqgrtwny6xwduazymvwt857uhe368ncuu9srgzwsuq2rhvfp8k55ewda2cng",
 "address": "cosmos1ghheq4u67c7szhg02whqj4sgg4tlt8mgdhteyk",
 "halted": false,
 "global_trading_paused": false,
 "chain_trading_paused": false,
 "chain_lp_actions_paused": false,
 "observed_fee_rate": "300000",
 "gas_rate": "450000",
 "gas_rate_units": "uatom",
 "outbound_tx_size": "1",
 "outbound_fee": "24512100",
 "dust_threshold": "1"
 },
 */

struct InboundAddress: Codable {
    let chain: String
    let address: String
    let router: String? // Router address for ERC20 tokens
    let halted: Bool
    let global_trading_paused: Bool?
    let chain_trading_paused: Bool?
    let chain_lp_actions_paused: Bool?
    let gas_rate: String
    let gas_rate_units: String
    let dust_threshold: String? // Dust threshold for the chain
    let outbound_fee: String? // Outbound fee for the chain
    let outbound_tx_size: String? // Outbound transaction size
}

extension InboundAddress {

    /// The chain cannot process an inbound transfer at all: it is halted, or
    /// THORChain has paused trading globally or for this chain. Any transfer to
    /// the inbound vault while this is true risks being stranded, so it gates
    /// swaps and secured-asset deposits alike.
    ///
    /// Deliberately excludes `chain_lp_actions_paused`. That flag is the
    /// `PauseLP<CHAIN>` mimir, which suspends only liquidity-provider add and
    /// withdraw — swaps and every other transaction keep processing while it is
    /// set, and THORChain leaves it set on healthy chains for long stretches.
    /// Folding it in here would block operations the chain is happily accepting.
    var isTradingHalted: Bool {
        halted || (global_trading_paused ?? false) || (chain_trading_paused ?? false)
    }

    /// Liquidity-provider add/withdraw is unavailable: either the chain cannot
    /// transact at all, or THORChain has paused LP actions specifically. Only
    /// LP flows may gate on this — it is strictly broader than
    /// `isTradingHalted`.
    var isLPActionsHalted: Bool {
        isTradingHalted || (chain_lp_actions_paused ?? false)
    }
}
