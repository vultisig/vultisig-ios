//
//  CoinTokenInfoView.swift
//  VultisigApp
//
//  Local facts about the asset — price, network, contract, decimals, explorer.
//  Unlike the market sections this needs no network call, so it renders for
//  every coin including the pool-priced ones that get no chart.
//

import SwiftUI

struct CoinTokenInfoView: View {
    let coin: Coin
    /// Spot price, passed in only when the chart is absent.
    ///
    /// With a chart on screen the price already headlines it, and repeating it
    /// four rows down is noise. Without one this is the only place the price
    /// appears, and the sheet has always shown it.
    let price: String?
    var onCopyContract: (String) -> Void
    var onOpenExplorer: () -> Void

    private enum Row: Hashable {
        case price(String)
        case network(String)
        case contract(String)
        case decimals(Int)
        case explorer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("tokenInfo".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                    view(for: row)
                        .commonListItemContainer(index: index, itemsCount: rows.count)
                }
            }
            .commonListContainer()
        }
    }

    private var rows: [Row] {
        var entries: [Row] = []

        if let price {
            entries.append(.price(price))
        }
        entries.append(.network(coin.chain.name))

        // Native coins have no contract to show — their `contractAddress` is
        // either empty or a chain-internal identifier, not something to copy.
        if !coin.isNativeToken, !coin.contractAddress.isEmpty {
            entries.append(.contract(coin.contractAddress))
        }
        entries.append(.decimals(coin.decimals))

        if Endpoint.getExplorerByCoinURL(coin: coin) != nil {
            entries.append(.explorer)
        }

        return entries
    }

    @ViewBuilder
    private func view(for row: Row) -> some View {
        switch row {
        case .price(let value):
            CoinMarketStatRow(title: "price".localized, value: value)
        case .network(let value):
            CoinMarketStatRow(title: "network".localized, value: value)
        case .contract(let contract):
            contractRow(contract)
        case .decimals(let value):
            CoinMarketStatRow(title: "decimals".localized, value: "\(value)")
        case .explorer:
            explorerRow
        }
    }

    private func contractRow(_ contract: String) -> some View {
        Button {
            onCopyContract(contract)
        } label: {
            CoinMarketStatRow(title: "contract".localized) {
                HStack(spacing: 6) {
                    Text(contract.truncatedAddress)
                        .font(Theme.fonts.priceBodyS)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Icon(.copies3, color: Theme.colors.textTertiary, size: 14)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("contract".localized)
        .accessibilityHint("copyContractAddress".localized)
    }

    private var explorerRow: some View {
        Button(action: onOpenExplorer) {
            CoinMarketStatRow(title: "viewOnExplorer".localized) {
                Icon(.arrowToCornerTopRight, color: Theme.colors.textTertiary, size: 14)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CoinTokenInfoView(
        coin: .example,
        price: "$63,916.00",
        onCopyContract: { _ in },
        onOpenExplorer: {}
    )
    .padding()
    .background(Theme.colors.bgPrimary)
}
