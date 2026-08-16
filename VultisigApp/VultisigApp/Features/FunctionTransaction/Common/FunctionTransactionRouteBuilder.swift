//
//  FunctionTransactionRouteBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import SwiftUI

struct FunctionTransactionRouteBuilder {

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
            buildFunctionTransactionScreen(vault: vault, transactionType: descriptor.destination)
        case .list(let descriptors):
            FunctionActionsScreen(vault: vault, descriptors: descriptors)
        }
    }

    @ViewBuilder
    func buildVerifyScreen(tx: SendTransaction, vault: Vault) -> some View {
        FunctionTransactionVerifyScreen(transaction: tx, vault: vault)
    }

    @ViewBuilder
    func buildFunctionTransactionScreen(
        vault: Vault,
        transactionType: FunctionTransactionType
    ) -> some View {
        FunctionTransactionScreen(vault: vault, transactionType: transactionType)
    }
}
