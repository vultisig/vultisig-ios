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
        case .verify(let transaction, let retrySignal, let vault):
            viewBuilder.buildVerifyScreen(transaction: transaction, retrySignal: retrySignal, vault: vault)
        case .pair(let vault, let transaction, let retrySignal, let keysignPayload, let fastVaultPassword):
            viewBuilder.buildPairScreen(
                vault: vault,
                transaction: transaction,
                retrySignal: retrySignal,
                keysignPayload: keysignPayload,
                fastVaultPassword: fastVaultPassword
            )
        case .keysign(let input, let transaction, let retrySignal):
            viewBuilder.buildKeysignScreen(input: input, transaction: transaction, retrySignal: retrySignal)
        case .done(let vault, let hash, let approveHash, let chain, let transaction, let progressLink):
            viewBuilder.buildDoneScreen(
                vault: vault,
                hash: hash,
                approveHash: approveHash,
                chain: chain,
                transaction: transaction,
                progressLink: progressLink
            )
        }
    }
}
