//
//  ThorchainNetwork.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-18.
//

import SwiftUI

struct ThorchainNetwork: Codable {
    let tns_register_fee_rune: String
    let tns_fee_per_block_rune: String
    let rune_price_in_tor: String?  // Added for bond calculations
    let vaults_migrating: Bool
}
