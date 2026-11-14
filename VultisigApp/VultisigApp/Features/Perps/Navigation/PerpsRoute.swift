//
//  PerpsRoute.swift
//  VultisigApp
//

import Foundation

enum PerpsRoute: Hashable {
    case hub(vault: Vault)
    case market(vault: Vault, coin: String)
    case position(vault: Vault, coin: String)
    case search(vault: Vault)
    case activity(vault: Vault)
    case withdraw(vault: Vault)
    case dryRunLog
}

extension PerpsRoute {
    /// The vault a route works on; nil for the vault-free debug log.
    var vault: Vault? {
        switch self {
        case .hub(let vault), .market(let vault, _), .position(let vault, _), .search(let vault), .activity(let vault), .withdraw(let vault):
            return vault
        case .dryRunLog:
            return nil
        }
    }
}
