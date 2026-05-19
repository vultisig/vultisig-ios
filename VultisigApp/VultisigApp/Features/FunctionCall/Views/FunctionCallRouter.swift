//
//  FunctionCallRouter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import SwiftUI

struct FunctionCallRouter {
    private let viewBuilder = FunctionCallRouteBuilder()

    @ViewBuilder
    func build(_ route: FunctionCallRoute) -> some View {
        switch route {
        case .details(let defaultCoin, let vault):
            viewBuilder.buildDetailsScreen(
                defaultCoin: defaultCoin,
                vault: vault
            )
        case .verify(let tx, let vault):
            viewBuilder.buildVerifyScreen(tx: tx, vault: vault)
        case .pair(let vault, let tx, let keysignPayload, let fastVaultPassword):
            viewBuilder.buildPairScreen(
                vault: vault,
                tx: tx,
                keysignPayload: keysignPayload,
                fastVaultPassword: fastVaultPassword
            )
        case .keysign(let input, let tx, let retrySignal):
            viewBuilder.buildKeysignScreen(input: input, tx: tx, retrySignal: retrySignal)
        case .functionTransaction(let vault, let transactionType):
            viewBuilder.buildFunctionTransactionScreen(
                vault: vault,
                transactionType: transactionType
            )
        }
    }
}
