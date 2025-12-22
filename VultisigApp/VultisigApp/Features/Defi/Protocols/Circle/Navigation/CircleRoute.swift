//
//  CircleRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 2025-12-19.
//

enum CircleRoute: Hashable {
    case main(vault: Vault)
    case deposit(vault: Vault)
    case withdraw(vault: Vault, model: CircleViewModel)
}
