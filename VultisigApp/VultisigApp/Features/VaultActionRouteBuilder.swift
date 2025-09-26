//
//  VaultActionRouteBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 25/09/2025.
//

import SwiftUI

struct VaultActionRouteBuilder {
    @ViewBuilder
    func buildActionRoute(action: VaultAction, sendTx: SendTransaction, vault: Vault) -> some View {
        switch action {
        case .send(let coin, let hasPreselectedCoin):
            SendRouteBuilder().buildDetailsScreen(
                coin: coin,
                hasPreselectedCoin: hasPreselectedCoin,
                tx: sendTx,
                vault: vault
            )
        case .swap(let fromCoin):
            SwapCryptoView(fromCoin: fromCoin, vault: vault)
        case .function(let coin):
            FunctionCallView(
                tx: sendTx,
                vault: vault,
                coin: coin
            )
        case .buy(let address, let blockChainCode, let coinType):
            SendRouteBuilder().buildBuyScreen(
                address: address,
                blockChainCode: blockChainCode,
                coinType: coinType
            )
            // TODO: - Action not implemented yet
//        case .sell, .receive:
            // TODO: - Action not implemented yet
        }
    }
}
