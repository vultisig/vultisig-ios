//
//  SendCryptoSecondaryDoneView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-07-09.
//

import SwiftUI

struct SendCryptoSecondaryDoneView: View {
    let input: SendCryptoContent
    let onDone: () -> Void
    
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
                .padding(.vertical, 24)
                .padding(.horizontal, 16)
            }
            
            continueButton
        }
    }
    
    var header: some View {
        getAssetCard(coin: input.coin, title: input.amountCrypto, description: input.amountFiat)
    }
    
    var summary: some View {
        VStack(spacing: 18) {
            Group {
                transactionHashLink
                separator
            }
            .showIf(input.hash.isNotEmpty)
            
            if let vaultName = homeViewModel.selectedVault?.name, vaultName.isNotEmpty {
                getCell(
                    title: "from",
                    description: vaultName,
                    bracketValue: input.fromAddress
                )
                separator
            }
            
            Group {
                getCell(
                    title: "to",
                    description: input.toAddress
                )
                separator
            }
            .showIf(input.toAddress.isNotEmpty)
            
            Group {
                getCell(
                    title: "memo",
                    description: input.memo
                )
                separator
            }
            .showIf(input.memo.isNotEmpty)
            
            
            getCell(
                    title: "network",
                    description: input.coin.chain.name,
                    icon: input.coin.chain.logo
                )
            
            separator
            
            getCell(
                title: "estNetworkFee",
                description: input.fee.crypto,
                secondaryDescription: input.fee.fiat
            )
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
                description: input.hash
            )
            
            Image(systemName: "arrow.up.forward.app")
                .font(.body14BrockmannMedium)
                .foregroundColor(.neutral0)
        }
    }
    
    var continueButton: some View {
        PrimaryButton(title: "done") {
            onDone()
            navigateToHome = true
        }
        .padding(24)
    }
    
    func openLink() {
        if let url = URL(string: input.explorerLink) {
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
    
    private func getCell(title: String, description: String, secondaryDescription: String? = nil, bracketValue: String? = nil, icon: String? = nil) -> some View {
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
            
            
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 2) {
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
                
                if let secondaryDescription {
                    Text(secondaryDescription)
                        .foregroundColor(.extraLightGray)
                        .lineLimit(1)
                }
            }
        }
        .font(.body14BrockmannMedium)
        .foregroundColor(.neutral0)
    }
}

#Preview {
    SendCryptoSecondaryDoneView(
        input: .init(
            coin: .example,
            amountCrypto: "30 RUNE",
            amountFiat: "US$ 200",
            hash: "44B447A6A8BCABCCEC6E3EE9DE366EA4E0CDFC2C0BFB59D51E1A12D27B0C51AB",
            explorerLink: "https://thorchain.net/tx/44B447A6A8BCABCCEC6E3EE9DE366EA4E0CDFC2C0BFB59D51E1A12D27B0C51AB",
            memo: "test",
            fromAddress: "thor1kkmnmgvd85puk8zsvqfxx36cqy9mxqret39t8z",
            toAddress: "thor1kkmnmgvd85puk8zsvqfxx36cqy9mxqret39t8z",
            fee: ("0.001 RUNE", "US$ 0.00")
        )
    ) {}
}
