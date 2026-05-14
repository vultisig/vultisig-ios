//
//  SendDetailsAssetTab.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-24.
//

import SwiftUI

struct SendDetailsAssetTab: View {
    let isExpanded: Bool
    @Bindable var viewModel: SendDetailsViewModel

    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        content
            .onAppear {
                setData()
            }
            .onChange(of: viewModel.coin, { _, _ in
                setData()
            })
            .onChange(of: viewModel.showCoinPickerSheet) { oldValue, newValue in
                handleAssetSelection(oldValue, newValue)
            }
            .onChange(of: isExpanded) { oldValue, newValue in
                handleAssetSelection(oldValue, newValue)
            }
            .onChange(of: viewModel.selectedChain) { _, newValue in
                guard let vault = appViewModel.selectedVault else { return }

                let nativeCoin = vault.coins.first(where: {
                    $0.chain == newValue && $0.isNativeToken == true
                })

                if let nativeCoin {
                    viewModel.fromAddress = nativeCoin.address
                    viewModel.coin = nativeCoin
                }
            }
            .clipped()
    }

    var content: some View {
        SendFormExpandableSection(isExpanded: isExpanded) {
            titleSection
        } content: {
            separator
            assetSelectionSection
        }
    }

    var titleSection: some View {
        HStack {
            Text(NSLocalizedString("asset", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textPrimary)

            if viewModel.assetSetupDone {
                doneSelectedAsset
                Spacer()
                doneEditTools
            } else {
                Spacer()
            }
        }
        .background(Background().opacity(0.01))
        .onTapGesture {
            viewModel.onSelect(tab: .asset)
        }
    }

    var separator: some View {
        LinearSeparator()
    }

    var assetSelectionSection: some View {
        VStack(spacing: 12) {
            chainSelection
            selectedCoinCell
        }
    }

    var chainSelection: some View {
        Button {
            viewModel.showChainPickerSheet.toggle()
        } label: {
            chainSelectionLabel
        }
    }

    var chainSelectionLabel: some View {
        HStack(spacing: 8) {
            chainSelectionTitle
            selectedChainCell
            Spacer()
        }
    }

    var chainSelectionTitle: some View {
        Text(NSLocalizedString("from", comment: ""))
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textTertiary)
    }

    var selectedChainCell: some View {
        SwapFromToChain(chain: viewModel.coin.chain)
    }

    var selectedCoinCell: some View {
        HStack {
            selectedCoinButton
            Spacer()
            selectedCoinBalance
        }
    }

    var selectedCoinButton: some View {
        Button {
            viewModel.showCoinPickerSheet.toggle()
        } label: {
            SwapFromToCoin(coin: viewModel.coin)
        }
    }

    var selectedCoinBalance: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Group {
                Text(NSLocalizedString("balance", comment: "")) +
                Text(": ") +
                Text(viewModel.coin.balanceString)
            }
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textPrimary)

            Text(viewModel.coin.balanceInFiat)
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    var doneSelectedAsset: some View {
        HStack(spacing: 4) {
            AsyncImageView(
                logo: viewModel.coin.logo,
                size: CGSize(width: 16, height: 16),
                ticker: viewModel.coin.ticker,
                tokenChainLogo: viewModel.coin.tokenChainLogo
            )

            Text("\(viewModel.coin.ticker)")
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.textTertiary)
        }
    }

    var doneEditTools: some View {
        SendDetailsTabEditTools(forTab: .asset, viewModel: viewModel)
    }

    private func setData() {
        viewModel.selectedChain = viewModel.coin.chain
    }

    private func handleAssetSelection(_ oldValue: Bool, _ newValue: Bool) {
        guard oldValue != newValue, !newValue else {
            return
        }

        if viewModel.selectedTab == .asset {
            viewModel.onSelect(tab: .address)
        }
        viewModel.assetSetupDone = true
    }
}
