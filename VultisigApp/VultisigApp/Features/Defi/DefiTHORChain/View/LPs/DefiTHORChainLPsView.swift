//
//  DefiTHORChainLPsView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiTHORChainLPsView: View {
    @ObservedObject var vault: Vault
    var onRemove: (LPPosition) -> Void
    var onAdd: (LPPosition) -> Void
    
    // TODO: - Fetch from RPC
    let lpPositions: [LPPosition] = [
        LPPosition(
            coin1: TokensStore.TokenSelectionAssets.first(where: { $0.ticker == "RUNE" && $0.isNativeToken }) ?? .example,
            coin1Amount: 800,
            coin2: TokensStore.TokenSelectionAssets.first(where: { $0.ticker == "ETH" && $0.isNativeToken && $0.chain == .ethereum }) ?? .example,
            coin2Amount: 2,
            apr: 0.05
        ),
        LPPosition(
            coin1: TokensStore.TokenSelectionAssets.first(where: { $0.ticker == "RUNE" && $0.isNativeToken }) ?? .example,
            coin1Amount: 800,
            coin2: TokensStore.TokenSelectionAssets.first(where: { $0.ticker == "USDC" && $0.chain == .ethereum }) ?? .example,
            coin2Amount: 2,
            apr: 0.1
        )
    ]
    
    var body: some View {
        LazyVStack(spacing: 14) {
            ForEach(lpPositions) { position in
                DefiTHORChainLPPositionView(
                    vault: vault,
                    position: position,
                    onRemove: { onRemove(position) },
                    onAdd: { onAdd(position) }
                )
            }
        }
    }
}

#Preview {
    DefiTHORChainLPsView(
        vault: .example,
        onRemove: { _ in },
        onAdd: { _ in },
    )
}
