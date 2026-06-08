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

    private var filteredRows: [ChainRowModel] {
        viewModel.filteredRows(in: vault)
    }

    var body: some View {
        Group {
            if !filteredRows.isEmpty {
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
        ForEach(Array(filteredRows.enumerated()), id: \.element.id) { index, row in
            VaultChainCellView(row: row, vault: vault) {
                onCopy(row.chain)
            }
            .commonListItemContainer(
                index: index,
                itemsCount: filteredRows.count
            )
        }
    }
}

#Preview {
    VaultMainChainListView(vault: .example) { _ in }
    onCustomizeChains: {}
    .environmentObject(VaultDetailViewModel())
}
