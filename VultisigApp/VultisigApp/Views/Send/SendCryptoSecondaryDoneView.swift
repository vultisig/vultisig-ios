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
            SendCryptoTransactionHashRowView(
                hash: input.hash,
                explorerLink: input.explorerLink,
                showCopy: false,
                showAlert: .constant(false)
            )
            .showIf(input.hash.isNotEmpty)
            
            separator
            
            if let vaultName = homeViewModel.selectedVault?.name, vaultName.isNotEmpty {
                SendCryptoTransactionDetailsRow(
                    title: "from",
                    description: vaultName,
                    bracketValue: input.fromAddress
                )
                separator
            }
            
            Group {
                SendCryptoTransactionDetailsRow(
                    title: "to",
                    description: input.toAddress
                )
                separator
            }
            .showIf(input.toAddress.isNotEmpty)
            
            Group {
                SendCryptoTransactionDetailsRow(
                    title: "memo",
                    description: input.memo
                )
                separator
            }
            .showIf(input.memo.isNotEmpty)
            
            
            SendCryptoTransactionDetailsRow(
                    title: "network",
                    description: input.coin.chain.name,
                    icon: input.coin.chain.logo
                )
            
            separator
            
            SendCryptoTransactionDetailsRow(
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
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(.neutral0)
            
            Text(description?.formatToFiat(includeCurrencySymbol: true) ?? "")
                .font(Theme.fonts.caption10)
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
