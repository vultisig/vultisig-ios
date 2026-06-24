//
//  TronRoute.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import Foundation

enum TronRoute: Hashable {
    case main(vault: Vault)
    case freeze(vault: Vault)
    case unfreeze(vault: Vault, frozenBandwidth: Decimal, frozenEnergy: Decimal)
}
