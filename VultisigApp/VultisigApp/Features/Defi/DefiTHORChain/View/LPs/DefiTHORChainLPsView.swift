//
//  DefiTHORChainLPsView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiTHORChainLPsView<EmptyStateView: View>: View {
    @ObservedObject var vault: Vault
    @ObservedObject var viewModel: DefiTHORChainLPsViewModel
    var onRemove: (LPPosition) -> Void
    var onAdd: (LPPosition) -> Void
    var emptyStateView: () -> EmptyStateView
    
    var showLoading: Bool {
        !viewModel.initialLoadingDone
    }
    
    var body: some View {
        LazyVStack(spacing: 14) {
            if !viewModel.hasLPPositions {
                emptyStateView()
            } else if showLoading {
                Text("this")
                ForEach(0..<2, id: \.self) { _ in
                    DefiTHORChainLPPositionSkeletonView()
                }
            } else {
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
}

#Preview {
    DefiTHORChainLPsView(
        vault: .example,
        viewModel: DefiTHORChainLPsViewModel(vault: .example),
        onRemove: { _ in },
        onAdd: { _ in },
        emptyStateView: { EmptyView() }
    )
}
