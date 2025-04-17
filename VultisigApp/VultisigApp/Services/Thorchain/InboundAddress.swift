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
    let halted: Bool
    let global_trading_paused: Bool
    let chain_trading_paused: Bool
    let chain_lp_actions_paused: Bool
    let gas_rate: String
    let gas_rate_units: String
}
