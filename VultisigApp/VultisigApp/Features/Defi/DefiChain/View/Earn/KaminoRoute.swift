//
//  KaminoRoute.swift
//  VultisigApp
//

import SwiftUI

/// Navigation into the Kamino Earn flows.
///
/// The vault travels as a `KaminoVaultDescriptor` — the registry's own entry —
/// rather than an address, so a screen can never be opened on a vault the app
/// does not curate.
enum KaminoRoute: Hashable {
    case deposit(vault: Vault, descriptor: KaminoVaultDescriptor)
}

struct KaminoRouter {

    @MainActor
    @ViewBuilder
    func build(_ route: KaminoRoute) -> some View {
        switch route {
        case .deposit(let vault, let descriptor):
            KaminoDepositScreen(vault: vault, descriptor: descriptor)
        }
    }
}
