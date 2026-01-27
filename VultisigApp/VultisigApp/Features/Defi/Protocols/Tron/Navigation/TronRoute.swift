//
//  TronRoute.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

enum TronRoute: Hashable {
    case main(vault: Vault)
    case freeze(vault: Vault)
    case unfreeze(vault: Vault, model: TronViewModel)
}
