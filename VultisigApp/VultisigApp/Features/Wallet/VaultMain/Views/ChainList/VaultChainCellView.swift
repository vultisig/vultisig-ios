//
//  VaultChainCellView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftUI

/// Pure value view over a `ChainRowModel`. It deliberately does not take the
/// `Vault`: the only thing it needed one for was building the navigation route,
/// and holding a reference type made the row impossible to compare, so SwiftUI
/// had to re-render every row whenever the list's parent body ran. The parent
/// owns navigation now and passes closures instead, which lets this be
/// `Equatable` and skipped while scrolling.
struct VaultChainCellView: View, Equatable {
    let row: ChainRowModel
    /// Identity, not rendering. The closures below capture the vault they were
    /// built for, and an equality-skipped row keeps the closures it was created
    /// with — so two identical-looking rows from different vaults must not
    /// compare equal, or copy/navigation would act on the previous vault.
    let vaultPubKeyECDSA: String
    var onSelect: () -> Void
    var onCopy: () -> Void

    static func == (lhs: VaultChainCellView, rhs: VaultChainCellView) -> Bool {
        lhs.row == rhs.row && lhs.vaultPubKeyECDSA == rhs.vaultPubKeyECDSA
    }

    var body: some View {
        Button(action: onSelect) {
            GroupedChainCellView(
                chain: row.chain,
                address: row.address,
                fiatBalance: row.fiatBalance,
                cryptoBalance: row.cryptoBalance,
                assetCount: row.assetCount,
                assetLogo: row.assetLogo,
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
            nativeTicker: "BTC",
            assetLogo: "btc",
            address: "bc1qexampleaddress",
            fiatBalance: "$0.00",
            cryptoBalance: "0 BTC",
            assetCount: 1
        ),
        vaultPubKeyECDSA: "preview",
        onSelect: {},
        onCopy: {}
    )
    .environmentObject(HomeViewModel())
}
