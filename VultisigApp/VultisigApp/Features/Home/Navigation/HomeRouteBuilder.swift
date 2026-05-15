//
//  HomeRouteBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 18/12/2025.
//

import SwiftUI

struct HomeRouteBuilder {

    @ViewBuilder
    func buildHome(showingVaultSelector: Bool) -> some View {
        HomeScreen(showingVaultSelector: showingVaultSelector)
    }

    @MainActor
    @ViewBuilder
    func buildActionRoute(action: VaultAction, sendTx: FunctionCallForm, vault: Vault) -> some View {
        switch action {
        case .send(let coin, let hasPreselectedCoin):
            SendRouteBuilder().buildDetailsScreen(
                seed: SendDetailsSeed.fromForm(
                    sendTx,
                    coin: coin,
                    vault: vault,
                    hasPreselectedCoin: hasPreselectedCoin
                )
            )
        case .swap(let fromCoin):
            SwapRouter().buildDetailsScreen(fromCoin: fromCoin, toCoin: nil, vault: vault)
        case .function(let coin):
            FunctionCallRouteBuilder().buildDetailsScreen(
                defaultCoin: coin,
                sendTx: sendTx,
                vault: vault
            )
        case .buy(let address, let blockChainCode, let coinType):
            SendRouteBuilder().buildBuyScreen(
                address: address,
                blockChainCode: blockChainCode,
                coinType: coinType
            )
        }
    }
}
