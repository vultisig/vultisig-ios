//
//  SwapRouter.swift
//  VultisigApp
//

import SwiftUI

struct SwapRouter {
    private let viewBuilder = SwapRouteBuilder()

    @ViewBuilder
    func build(_ route: SwapRoute) -> some View {
        switch route {
        case .root(let fromCoin, let toCoin, let vault):
            viewBuilder.buildDetailsScreen(fromCoin: fromCoin, toCoin: toCoin, vault: vault)
        case .verify(let tx, let vault):
            viewBuilder.buildVerifyScreen(tx: tx, vault: vault)
        case .pair(let vault, let tx, let keysignPayload, let fastVaultPassword):
            viewBuilder.buildPairScreen(
                vault: vault,
                tx: tx,
                keysignPayload: keysignPayload,
                fastVaultPassword: fastVaultPassword
            )
        case .keysign(let input, let tx):
            viewBuilder.buildKeysignScreen(input: input, tx: tx)
        case .done(let vault, let hash, let approveHash, let chain, let tx, let progressLink):
            viewBuilder.buildDoneScreen(
                vault: vault,
                hash: hash,
                approveHash: approveHash,
                chain: chain,
                tx: tx,
                progressLink: progressLink
            )
        }
    }
}
