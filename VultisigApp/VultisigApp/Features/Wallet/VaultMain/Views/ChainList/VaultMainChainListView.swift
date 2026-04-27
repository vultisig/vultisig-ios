//
//  VaultMainChainListView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftUI

struct VaultMainChainListView: View {
    @ObservedObject var vault: Vault
    @EnvironmentObject var viewModel: VaultDetailViewModel

    var onCopy: (Chain) -> Void
    var onCustomizeChains: () -> Void

    private var filteredChains: [Chain] {
        viewModel.filteredChains(in: vault)
    }

    var body: some View {
        Group {
            if !filteredChains.isEmpty {
                chainList
            } else {
                CustomizeChainsActionBanner(
                    showButton: vault.canCustomizeChains,
                    onCustomizeChains: onCustomizeChains
                )
            }
        }
    }

    var chainList: some View {
        ForEach(Array(filteredChains.enumerated()), id: \.element) { index, chain in
            VaultChainCellView(chain: chain, vault: vault) {
                onCopy(chain)
            }
            .commonListItemContainer(
                index: index,
                itemsCount: filteredChains.count
            )
        }
    }
}

#Preview {
    VaultMainChainListView(vault: .example) { _ in }
    onCustomizeChains: {}
    .environmentObject(VaultDetailViewModel())
}
