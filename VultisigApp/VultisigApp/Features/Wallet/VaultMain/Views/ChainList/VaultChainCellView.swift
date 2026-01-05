//
//  VaultChainCellView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftUI

struct VaultChainCellView: View {
    @ObservedObject var group: GroupedChain
    let vault: Vault
    var onCopy: () -> Void

    @Environment(\.router) var router

    @EnvironmentObject var homeViewModel: HomeViewModel

    var body: some View {
        Button {
            router.navigate(to: VaultRoute.chainDetail(group: group, vault: vault))
        } label: {
            GroupedChainCellView(
                group: group,
                vault: vault,
                fiatBalance: group.totalBalanceInFiatString,
                cryptoBalance: group.nativeCoin.balanceStringWithTicker,
                onCopy: onCopy
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VaultChainCellView(group: .example, vault: .example) {}
        .environmentObject(HomeViewModel())
}
