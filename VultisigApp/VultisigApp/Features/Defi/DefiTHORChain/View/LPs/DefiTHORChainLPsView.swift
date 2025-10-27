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
    @Binding var loadingBalances: Bool
    var onRemove: (LPPosition) -> Void
    var onAdd: (LPPosition) -> Void
    var emptyStateView: () -> EmptyStateView
    
    var showLoading: Bool {
        loadingBalances && !viewModel.setupDone
    }
    
    var body: some View {
        LazyVStack(spacing: 14) {
            if showLoading {
                ForEach(0..<2, id: \.self) { _ in
                    DefiTHORChainLPPositionSkeletonView()
                }
            } else if viewModel.hasLPPositions {
                ForEach(viewModel.lpPositions) { position in
                    DefiTHORChainLPPositionView(
                        vault: vault,
                        position: position,
                        onRemove: { onRemove(position) },
                        onAdd: { onAdd(position) }
                    )
                }
            } else {
                emptyStateView()
            }
        }
    }
}

#Preview {
    DefiTHORChainLPsView(
        vault: .example,
        viewModel: DefiTHORChainLPsViewModel(vault: .example),
        loadingBalances: .constant(false),
        onRemove: { _ in },
        onAdd: { _ in },
        emptyStateView: { EmptyView() }
    )
}
