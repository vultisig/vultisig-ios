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
            .sheet(isPresented: $viewModel.showChainPickerSheet, content: {
                if let vault = homeViewModel.selectedVault {
                    SwapChainPickerView(
                        vault: vault,
                        showSheet: $viewModel.showChainPickerSheet,
                        selectedChain: $viewModel.selectedChain,
                        selectedCoin: $tx.coin
                    )
                }
            })
            .sheet(isPresented: $viewModel.showCoinPickerSheet, content: {
                if let vault = homeViewModel.selectedVault {
                    SwapCoinPickerView(
                        vault: vault,
                        showSheet: $viewModel.showCoinPickerSheet,
                        selectedCoin: $tx.coin,
                        selectedChain: $viewModel.selectedChain
                    )
                }
            })
            .onChange(of: viewModel.showCoinPickerSheet) { oldValue, newValue in
                handleAssetSelection(oldValue, newValue)
            }
            .onChange(of: isExpanded) { oldValue, newValue in
                handleAssetSelection(oldValue, newValue)
            }
    }
    
    var content: some View {
        VStack(spacing: 16) {
            titleSection
            
            if isExpanded {
                separator
                assetSelectionSection
            }
        }
        .padding(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue200, lineWidth: 1)
        )
        .padding(1)
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
        .onTapGesture {
            viewModel.selectedTab = .Asset
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
        SendDetailsTabEditTools(forTab: .Asset, viewModel: viewModel)
    }
    
    private func setData() {
        viewModel.selectedChain = tx.coin.chain
    }
    
    private func handleAssetSelection(_ oldValue: Bool, _ newValue: Bool) {
        guard oldValue != newValue, !newValue else {
            return
        }
        
        viewModel.selectedTab = .Address
        viewModel.assetSetupDone = true
    }
}

#Preview {
    SendDetailsAssetTab(isExpanded: true, tx: SendTransaction(), viewModel: SendDetailsViewModel(), sendCryptoViewModel: SendCryptoViewModel())
}
