//
//  SendRouter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import SwiftUI

struct SendRouter {
    private let viewBuilder = SendRouteBuilder()

    @MainActor
    @ViewBuilder
    func build(_ route: SendRoute) -> some View {
        switch route {
        case .details(let seed):
            viewBuilder.buildDetailsScreen(seed: seed)
        case .verify(let tx, let retrySignal, let vault):
            viewBuilder.buildVerifyScreen(tx: tx, retrySignal: retrySignal, vault: vault)
        case .pairing(let vault, let tx, let retrySignal, let keysignPayload, let fastVaultPassword):
            viewBuilder.buildPairScreen(
                vault: vault,
                tx: tx,
                retrySignal: retrySignal,
                keysignPayload: keysignPayload,
                fastVaultPassword: fastVaultPassword
            )
        case .keysign(let input, let tx, let retrySignal):
            viewBuilder.buildKeysignScreen(input: input, tx: tx, retrySignal: retrySignal)
        case .done(let vault, let hash, let chain, let tx, let keysignPayload):
            viewBuilder.buildDoneScreen(
                vault: vault,
                hash: hash,
                chain: chain,
                tx: tx,
                keysignPayload: keysignPayload
            )
        case .transactionDetails(let input):
            viewBuilder.buildTransactionDetailsScreen(input: input)
        }
    }
}
