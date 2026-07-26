//
//  FunctionCallRouteBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import SwiftUI

struct FunctionCallRouteBuilder {

    @ViewBuilder
    func buildDetailsScreen(
        defaultCoin: Coin?,
        vault: Vault
    ) -> some View {
        FunctionCallDetailsScreen(
            vault: vault,
            defaultCoin: defaultCoin
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
