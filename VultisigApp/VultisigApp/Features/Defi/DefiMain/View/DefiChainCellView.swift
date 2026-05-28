//
//  DefiChainCellView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/10/2025.
//

import SwiftUI

struct DefiChainCellView: View {
    let chain: Chain
    let vault: Vault

    @EnvironmentObject var homeViewModel: HomeViewModel

    private let service = DefiBalanceService()

    @State var balanceFiat: String = ""
    @State var positionsSubtitle: String = ""

    private var defiBalance: Decimal {
        vault.coins(for: chain).totalDefiBalanceInFiatDecimal
    }

    var body: some View {
        GroupedChainCellView(
            chain: chain,
            vault: vault,
            fiatBalance: balanceFiat,
            cryptoBalance: "",
            trailingSubtitleOverride: positionsSubtitle
        )
        .buttonStyle(.plain)
        .onAppear { updateBalance() }
        .onChange(of: defiBalance) { _, _ in
            updateBalance()
        }
    }

    func updateBalance() {
        balanceFiat = service.totalBalanceInFiatString(for: chain, vault: vault)
        let count = service.defiPositionCount(for: chain, vault: vault)
        positionsSubtitle = count > 0
            ? String(format: "defiChainPositionsCount".localized, count)
            : "defiChainNoPositions".localized
    }
}

#Preview {
    DefiChainCellView(chain: .ethereum, vault: .example)
        .environmentObject(HomeViewModel())
}
