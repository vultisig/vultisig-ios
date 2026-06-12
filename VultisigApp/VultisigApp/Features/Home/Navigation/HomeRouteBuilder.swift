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
    func buildActionRoute(action: VaultAction, vault: Vault) -> some View {
        switch action {
        case .send(let coin, let hasPreselectedCoin, let prefilledToAddress, let prefilledAmount, let prefilledMemo):
            if let resolvedCoin = coin ?? vault.coins.first(where: { $0.isNativeToken }) ?? vault.coins.first {
                SendRouteBuilder().buildDetailsScreen(
                    seed: SendDetailsSeed.fromAction(
                        coin: resolvedCoin,
                        vault: vault,
                        hasPreselectedCoin: hasPreselectedCoin,
                        prefilledToAddress: prefilledToAddress,
                        prefilledAmount: prefilledAmount,
                        prefilledMemo: prefilledMemo
                    )
                )
            } else {
                EmptyView()
            }
        case .swap(let fromCoin):
            SwapRouter().buildDetailsScreen(fromCoin: fromCoin, toCoin: nil, vault: vault)
        case .function(let coin):
            FunctionCallRouteBuilder().buildDetailsScreen(
                defaultCoin: coin,
                vault: vault
            )
        case .buy(let address, let blockChainCode, let coinType):
            SendRouteBuilder().buildBuyScreen(
                address: address,
                blockChainCode: blockChainCode,
                coinType: coinType
            )
        case .qbtcClaim(let vault):
            // Defense-in-depth: every upstream entry to `.qbtcClaim` is
            // already gated by `QBTCConfig.isFeatureEnabled`. Guarding here
            // too means any future caller that wires a new entry point
            // without remembering the flag still can't surface the flow.
            if QBTCConfig.isFeatureEnabled {
                QBTCClaimScreen(vault: vault)
            } else {
                EmptyView()
            }
        }
    }
}
