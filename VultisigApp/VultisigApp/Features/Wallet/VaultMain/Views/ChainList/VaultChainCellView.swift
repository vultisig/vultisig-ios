//
//  VaultChainCellView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftUI

struct VaultChainCellView: View {
    let chain: Chain
    let vault: Vault
    var onCopy: () -> Void

    @Environment(\.router) var router

    @EnvironmentObject var homeViewModel: HomeViewModel

    private var chainCoins: [Coin] { vault.coins(for: chain) }

    private var fiatBalance: String {
        chainCoins.totalBalanceInFiatDecimal.formatToFiat(includeCurrencySymbol: true)
    }

    private var cryptoBalance: String {
        vault.nativeCoin(for: chain)?.balanceStringWithTicker ?? ""
    }

    var body: some View {
        Button {
            router.navigate(to: VaultRoute.chainDetail(chain: chain, vault: vault))
        } label: {
            GroupedChainCellView(
                chain: chain,
                vault: vault,
                fiatBalance: fiatBalance,
                cryptoBalance: cryptoBalance,
                onCopy: onCopy
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VaultChainCellView(chain: .bitcoin, vault: .example) {}
        .environmentObject(HomeViewModel())
}
