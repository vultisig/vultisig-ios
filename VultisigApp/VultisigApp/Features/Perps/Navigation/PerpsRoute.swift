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
