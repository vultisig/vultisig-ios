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
    @Environment(\.router) var router

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
        let rows = filteredRows
        // Lazy so rows are realized as they scroll in rather than all at once:
        // the surrounding surface is drawn by `commonListContainer`, which no
        // longer needs the whole list laid out to clip it.
        return LazyVStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                VaultChainCellView(
                    row: row,
                    vaultPubKeyECDSA: vault.pubKeyECDSA,
                    onSelect: { navigate(to: row.chain) },
                    onCopy: { onCopy(row.chain) }
                )
                .equatable()
                .commonListItemContainer(
                    index: index,
                    itemsCount: rows.count
                )
            }
        }
        .commonListContainer()
    }

    private func navigate(to chain: Chain) {
        router.navigate(to: VaultRoute.chainDetail(chain: chain, vault: vault))
    }
}

#Preview {
    VaultMainChainListView(vault: .example) { _ in }
    onCustomizeChains: {}
    .environmentObject(VaultDetailViewModel())
}
