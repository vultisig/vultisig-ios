//
//  SendDetailsAssetTab.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-24.
//

import SwiftUI

struct SendDetailsAssetTab: View {
    let isExpanded: Bool
    @ObservedObject var tx: SendTransaction
    @ObservedObject var viewModel: SendDetailsViewModel
    @ObservedObject var sendCryptoViewModel: SendCryptoViewModel
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var body: some View {
        content
            .onAppear {
                setData()
            }
            .onChange(of: tx.coin, { oldValue, newValue in
                setData()
            })
            // chain selector
            .sheet(isPresented: $viewModel.showChainPickerSheet, content: {
                if let vault = homeViewModel.selectedVault {
                    SwapChainPickerView(
                        vault: vault,
                        showSheet: $viewModel.showChainPickerSheet,
                        selectedChain: $viewModel.selectedChain
                    )
                }
            })
            // coin selector
            .sheet(isPresented: $viewModel.showCoinPickerSheet, content: {
                if let vault = homeViewModel.selectedVault {
                    SwapCoinPickerView(
                        vault: vault,
                        showSheet: $viewModel.showCoinPickerSheet,
                        selectedCoin: $tx.coin,
                        selectedChain: viewModel.selectedChain
                    )
                }
            })
            .onChange(of: viewModel.showCoinPickerSheet) { oldValue, newValue in
                handleAssetSelection(oldValue, newValue)
            }
            .onChange(of: isExpanded) { oldValue, newValue in
                handleAssetSelection(oldValue, newValue)
            }
            .onChange(of: viewModel.selectedChain) { oldValue, newValue in
                guard let vault = homeViewModel.selectedVault else { return }
                print("Selected chain changed: \(String(describing: newValue)) , update from address")
                let coin = vault.coins.first(where: { $0.chain == newValue })
                tx.fromAddress = coin?.address ?? ""
                // Update coin when chain changes
                if let coin {
                    tx.coin = coin
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
                .font(.body14BrockmannMedium)
                .foregroundColor(.neutral0)
            
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
            .font(.body12BrockmannMedium)
            .foregroundColor(.extraLightGray)
    }
    
    var selectedChainCell: some View {
        SwapFromToChain(chain: tx.coin.chain)
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
            SwapFromToCoin(coin: tx.coin)
        }
    }
    
    var selectedCoinBalance: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Group {
                Text(NSLocalizedString("balance", comment: "")) +
                Text(": ") +
                Text(tx.coin.balanceString)
            }
            .font(.body14BrockmannMedium)
            .foregroundColor(.neutral0)
            
            Text(tx.coin.balanceInFiat)
                .font(.body12BrockmannMedium)
                .foregroundColor(.extraLightGray)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    
    var doneSelectedAsset: some View {
        HStack(spacing: 4) {
            AsyncImageView(
                logo: tx.coin.logo,
                size: CGSize(width: 16, height: 16),
                ticker: tx.coin.ticker,
                tokenChainLogo: tx.coin.tokenChainLogo
            )
            
            Text("\(tx.coin.ticker)")
                .font(.body12BrockmannMedium)
                .foregroundColor(.extraLightGray)
        }
    }
    
    var doneEditTools: some View {
        SendDetailsTabEditTools(forTab: .asset, viewModel: viewModel)
    }
    
    private func setData() {
        viewModel.selectedChain = tx.coin.chain
    }
    
    private func handleAssetSelection(_ oldValue: Bool, _ newValue: Bool) {
        guard oldValue != newValue, !newValue else {
            return
        }
        
        viewModel.onSelect(tab: .address)
        viewModel.assetSetupDone = true
    }
}

#Preview {
    SendDetailsAssetTab(
        isExpanded: true,
        tx: SendTransaction(),
        viewModel: SendDetailsViewModel(),
        sendCryptoViewModel: SendCryptoViewModel()
    )
}
