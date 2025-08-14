//
//  SendRouter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import SwiftUI

struct SendRouter {
    private let navigationRouter: NavigationRouter
    private let viewBuilder = SendRouteBuilder()
    
    init(navigationRouter: NavigationRouter) {
        self.navigationRouter = navigationRouter
    }
    
    @ViewBuilder
    func build(_ route: SendRoute) -> some View {
        switch route {
        case .details(let input):
            viewBuilder.buildDetailsScreen(
                coin: input.coin,
                hasPreselectedCoin: input.hasPreselectedCoin,
                tx: input.tx,
                vault: input.vault
            )
        case .verify(let tx, let vault):
            viewBuilder.buildVerifyScreen(tx: tx, vault: vault)
        case .pairing(let vault, let tx, let keysignPayload, let fastVaultPassword):
            viewBuilder.buildPairScreen(
                vault: vault,
                tx: tx,
                keysignPayload: keysignPayload,
                fastVaultPassword: fastVaultPassword
            )
        case .keysign(let input, let tx):
            viewBuilder.buildKeysignScreen(input: input, tx: tx)
        case .done(let vault, let hash, let chain, let tx):
            viewBuilder.buildDoneScreen(
                vault: vault,
                hash: hash,
                chain: chain,
                tx: tx
            )
        }
    }
}

struct SendRouteInput: Hashable {
    let coin: Coin?
    let hasPreselectedCoin: Bool
    let tx: SendTransaction
    let vault: Vault
}
