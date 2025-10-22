//
//  DefiTHORChainLPsView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiTHORChainLPsView: View {
    @ObservedObject var vault: Vault
    @ObservedObject var viewModel: DefiTHORChainLPsViewModel
    var onRemove: (LPPosition) -> Void
    var onAdd: (LPPosition) -> Void
    
    var body: some View {
        LazyVStack(spacing: 14) {
            ForEach(viewModel.lpPositions) { position in
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
        viewModel: DefiTHORChainLPsViewModel(vault: .example),
        onRemove: { _ in },
        onAdd: { _ in }
    )
}
