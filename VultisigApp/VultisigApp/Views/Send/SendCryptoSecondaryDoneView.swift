//
//  SendCryptoSecondaryDoneView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-07-09.
//

import SwiftUI

struct SendCryptoSecondaryDoneView: View {
    let sendTransaction: SendTransaction?
    let hash: String
    let explorerLink: String
    
    @State var navigateToHome = false
    
    @Environment(\.openURL) var openURL
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var body: some View {
        container
            .navigationDestination(isPresented: $navigateToHome) {
                if let vault = homeViewModel.selectedVault {
                    HomeView(selectedVault: vault)
                }
            }
    }
    
    var content: some View {
        VStack {
            ScrollView {
                VStack {
                    header
                    summary
                }
                .padding(24)
            }
            
            continueButton
        }
    }
    
    var header: some View {
        getAssetCard(coin: sendTransaction?.coin, title: "\(sendTransaction?.amount ?? "") \(sendTransaction?.coin.ticker ?? "")", description: sendTransaction?.amountInFiat)
    }
    
    var summary: some View {
        VStack(spacing: 18) {
            transactionHashLink
            
            separator
            
            if let vaultName = homeViewModel.selectedVault?.name {
                getCell(
                    title: "from",
                    description: vaultName,
                    bracketValue: sendTransaction?.fromAddress ?? ""
                )
            }
            
            separator
            
            getCell(
                title: "to",
                description: sendTransaction?.toAddress ?? ""
            )
            
            separator
            
            if let chainName = sendTransaction?.coin.chain.name {
                getCell(
                    title: "network",
                    description: chainName,
                    icon: sendTransaction?.coin.chain.logo
                )
            }
            
            separator
            
            if let gasInReadable = sendTransaction?.gasInReadable {
                getCell(
                    title: "estNetworkFee",
                    description: gasInReadable
                )
            }
        }
        .padding(24)
        .background(Color.blue600)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue200, lineWidth: 1)
        )
    }
    
    var separator: some View {
        Separator()
            .opacity(0.8)
    }
    
    var transactionHashLink: some View {
        Button {
            openLink()
        } label: {
            transactionHashLabel
        }
    }
    
    var transactionHashLabel: some View {
        HStack {
            getCell(
                title: "transactionHash",
                description: hash
            )
            
            Image(systemName: "arrow.up.forward.app")
                .font(.body14BrockmannMedium)
                .foregroundColor(.neutral0)
        }
    }
    
    var continueButton: some View {
        PrimaryButton(title: "done") {
            if let send = sendTransaction {
                send.reset(coin: send.coin)
            }
            navigateToHome = true
        }
        .padding(24)
    }
    
    func openLink() {
        let urlString = explorerLink
        
        if let url = URL(string: urlString) {
            openURL(url)
        }
    }
    
    private func getAssetCard(coin: Coin?, title: String, description: String?) -> some View {
        VStack(spacing: 4) {
            if let coin {
                AsyncImageView(
                    logo: coin.logo,
                    size: CGSize(width: 32, height: 32),
                    ticker: coin.ticker,
                    tokenChainLogo: coin.tokenChainLogo
                )
                .padding(.bottom, 8)
            }
            
            Text(title)
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)
            
            Text(description?.formatToFiat(includeCurrencySymbol: true) ?? "")
                .font(.body10BrockmannMedium)
                .foregroundColor(.extraLightGray)
        }
        .frame(height: 130)
        .frame(maxWidth: .infinity)
        .background(Color.blue600)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue600, lineWidth: 1)
        )
    }
    
    private func getCell(title: String, description: String, bracketValue: String? = nil, icon: String? = nil) -> some View {
        HStack(spacing: 2) {
            Text(NSLocalizedString(title, comment: ""))
                .foregroundColor(.extraLightGray)
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer()
            
            if let icon {
                Image(icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .cornerRadius(32)
            }
            
            Text(description)
                .foregroundColor(.neutral0)
                .lineLimit(1)
                .truncationMode(.middle)
            
            if let bracketValue {
                Text("(\(bracketValue))")
                    .foregroundColor(.extraLightGray)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.body14BrockmannMedium)
        .foregroundColor(.neutral0)
    }
}

#Preview {
    SendCryptoSecondaryDoneView(sendTransaction: SendTransaction(), hash: "", explorerLink: "")
}
