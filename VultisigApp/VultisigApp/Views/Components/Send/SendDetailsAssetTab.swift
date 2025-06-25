//
//  SendDetailsAssetTab.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-24.
//

import SwiftUI

struct SendDetailsAssetTab: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var viewModel: SendDetailsViewModel
    
    @State var isExpanded: Bool = true
    
    var body: some View {
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
            SwapFromToCoin(coin: tx.coin)
            Spacer()
            selectedCoinBalance
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
}

#Preview {
    SendDetailsAssetTab(tx: SendTransaction(), viewModel: SendDetailsViewModel())
}
