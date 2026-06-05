//
//  VaultChainCellView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftUI

struct VaultChainCellView: View {
    let row: ChainRowModel
    let vault: Vault
    var onCopy: () -> Void

    @Environment(\.router) var router

    var body: some View {
        Button {
            router.navigate(to: VaultRoute.chainDetail(chain: row.chain, vault: vault))
        } label: {
            GroupedChainCellView(
                chain: row.chain,
                address: row.address,
                fiatBalance: row.fiatBalance,
                cryptoBalance: row.cryptoBalance,
                assetCount: row.assetCount,
                onCopy: onCopy
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VaultChainCellView(
        row: ChainRowModel(
            chain: .bitcoin,
            address: "bc1qexampleaddress",
            fiatBalance: "$0.00",
            cryptoBalance: "0 BTC",
            assetCount: 1
        ),
        vault: .example
    ) {}
    .environmentObject(HomeViewModel())
}
