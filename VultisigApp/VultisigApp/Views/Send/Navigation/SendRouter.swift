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
                tx: input.tx,
                sendCryptoViewModel: input.sendCryptoViewModel,
                sendDetailsViewModel: input.sendDetailsViewModel,
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
    static func == (lhs: SendRouteInput, rhs: SendRouteInput) -> Bool {
        lhs.tx == rhs.tx
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(tx)
    }
    
    let tx: SendTransaction
    let vault: Vault
    let sendCryptoViewModel: SendCryptoViewModel
    let sendDetailsViewModel: SendDetailsViewModel
    
    init(tx: SendTransaction, vault: Vault, sendCryptoViewModel: SendCryptoViewModel, sendDetailsViewModel: SendDetailsViewModel) {
        self.tx = tx
        self.vault = vault
        self.sendCryptoViewModel = sendCryptoViewModel
        self.sendDetailsViewModel = sendDetailsViewModel
    }
}
