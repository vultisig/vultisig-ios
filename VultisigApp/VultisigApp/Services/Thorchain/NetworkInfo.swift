//
//  NetworkInfo.swift
//  VultisigApp
//
//  Created by Johnny Luo on 17/4/2025.
//

/*
 {
 "bond_reward_rune": "9352984558392",
 "total_bond_units": "3339546",
 "available_pools_rune": "4979376438490624",
 "vaults_liquidity_rune": "6299709046159019",
 "effective_security_bond": "6538209326565853",
 "total_reserve": "7409422323013332",
 "vaults_migrating": false,
 "gas_spent_rune": "179282527796318",
 "gas_withheld_rune": "231180386614277",
 "outbound_fee_multiplier": "1000",
 "native_outbound_fee_rune": "2000000",
 "native_tx_fee_rune": "2000000",
 "tns_register_fee_rune": "1000000000",
 "tns_fee_per_block_rune": "20",
 "rune_price_in_tor": "113614412",
 "tor_price_in_rune": "88017003"
 }
 */

struct ThorchainNetworkInfo: Decodable {
    let native_tx_fee_rune: String
}
