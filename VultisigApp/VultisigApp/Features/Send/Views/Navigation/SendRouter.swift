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
        case .verify(let tx, let retrySignal, let vault, let prebuiltKeysignPayload):
            viewBuilder.buildVerifyScreen(
                tx: tx,
                retrySignal: retrySignal,
                vault: vault,
                prebuiltKeysignPayload: prebuiltKeysignPayload
            )
        case .transactionDetails(let input):
            viewBuilder.buildTransactionDetailsScreen(input: input)
        }
    }
}
