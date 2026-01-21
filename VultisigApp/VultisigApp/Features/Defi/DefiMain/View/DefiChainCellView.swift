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

    private let service = DefiBalanceService()

    @State var balanceFiat: String = ""

    var body: some View {
        if group.name == "Circle" {
             DefiCircleRow(vault: vault)
        } else {
            GroupedChainCellView(
                group: group,
                vault: vault,
                fiatBalance: balanceFiat,
                cryptoBalance: group.nativeCoin.defiBalanceStringWithTicker
            )
            .buttonStyle(.plain)
            .onAppear { updateBalance() }
            .onChange(of: group.defiBalanceInFiatDecimal) { _, _ in
                updateBalance()
            }
        }
    }

    func updateBalance() {
        balanceFiat = service.totalBalanceInFiatString(for: group.chain, vault: vault)
    }
}

#Preview {
    DefiChainCellView(group: .example, vault: .example)
        .environmentObject(HomeViewModel())
}
