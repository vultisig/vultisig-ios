//
//  FunctionCallRouteBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import SwiftUI

struct FunctionCallRouteBuilder {

    /// The Functions entry point. A chain with one operation opens that
    /// operation directly — a list screen with a single row is a tap nobody
    /// should have to make — and every other chain gets the list.
    @ViewBuilder
    func buildActionsScreen(
        defaultCoin: Coin?,
        vault: Vault
    ) -> some View {
        let coin = FunctionActionCatalog.resolveCoin(defaultCoin: defaultCoin, vault: vault)
        switch FunctionActionCatalog.entry(for: coin) {
        case .action(let descriptor):
            buildDestinationScreen(descriptor.destination, coin: coin, vault: vault)
        case .list(let descriptors):
            FunctionActionsScreen(vault: vault, coin: coin, descriptors: descriptors)
        }
    }

    /// The view a descriptor names. Mirrors `FunctionCallRoute.route(for:…)`
    /// for the passthrough, which builds its destination in place rather than
    /// pushing the user through a screen they never saw.
    @ViewBuilder
    func buildDestinationScreen(
        _ destination: FunctionActionDescriptor.Destination,
        coin: Coin,
        vault: Vault
    ) -> some View {
        switch destination {
        case .transaction(let transactionType):
            buildFunctionTransactionScreen(vault: vault, transactionType: transactionType)
        case .legacyFunctionCall(let functionCallType):
            buildDetailsScreen(defaultCoin: coin, vault: vault, preselected: functionCallType)
        }
    }

    @ViewBuilder
    func buildDetailsScreen(
        defaultCoin: Coin?,
        vault: Vault,
        preselected: FunctionCallType?
    ) -> some View {
        FunctionCallDetailsScreen(
            vault: vault,
            defaultCoin: defaultCoin,
            preselected: preselected
        )
    }

    @ViewBuilder
    func buildVerifyScreen(tx: SendTransaction, vault: Vault) -> some View {
        FunctionCallVerifyScreen(transaction: tx, vault: vault)
    }

    @ViewBuilder
    func buildFunctionTransactionScreen(
        vault: Vault,
        transactionType: FunctionTransactionType
    ) -> some View {
        FunctionTransactionScreen(vault: vault, transactionType: transactionType)
    }
}
