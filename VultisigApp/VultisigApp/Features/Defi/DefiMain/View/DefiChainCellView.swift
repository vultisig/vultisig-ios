//
//  DefiChainCellView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/10/2025.
//

import SwiftUI

struct DefiChainCellView: View {
    @ObservedObject var group: GroupedChain
    let vault: Vault
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var body: some View {
        GroupedChainCellView(
            group: group,
            vault: vault,
            fiatBalance: { group.defiBalanceInFiatString },
            cryptoBalance: { group.nativeCoin.defiBalanceStringWithTicker }
        )
        .buttonStyle(.plain)
    }
}

#Preview {
    DefiChainCellView(group: .example, vault: .example)
        .environmentObject(HomeViewModel())
}
