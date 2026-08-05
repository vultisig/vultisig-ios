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
            address: "",
            fiatBalance: balanceFiat,
            cryptoBalance: "",
            assetCount: 0,
            trailingSubtitleOverride: positionsSubtitle
        )
        .buttonStyle(.plain)
        .onAppear { updateBalance() }
        .onChange(of: defiBalance) { _, _ in
            updateBalance()
        }
        // Positions that do not live on a wallet coin — Kamino Earn deposits,
        // stake and LP rows — change the balance and count above without
        // touching `defiBalance`, so the row has to be told. Same signal the
        // aggregate and chain-detail balance views already observe.
        .onReceive(NotificationCenter.default.publisher(for: .defiPositionsDidChange)) { _ in
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
