//
//  SendCryptoDoneContentView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/07/2025.
//

import SwiftUI
import RiveRuntime

struct SendCryptoDoneContentView: View {
    let input: SendCryptoContent
    let onDone: () -> Void
    
    @State var animationVM: RiveViewModel? = nil
    
    var body: some View {
        ScrollView {
            VStack {
                animation
                getAssetCard(coin: input.coin, title: input.amountCrypto, description: input.amountFiat)
                
                NavigationLink {
                    SendCryptoSecondaryDoneView(input: input) {
                        onDone()
                    }
                } label: {
                    transactionDetails
                }
            }
        }
        .onLoad {
            animationVM = RiveViewModel(fileName: "vaultCreatedAnimation", autoPlay: true)
        }
    }
    
    var transactionDetails: some View {
        HStack {
            Text(NSLocalizedString("transactionDetails", comment: ""))
            Spacer()
            Image(systemName: "chevron.right")
        }
        .font(.body14BrockmannMedium)
        .foregroundColor(.lightText)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.blue600)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue400, lineWidth: 1)
        )
        .padding(.top, 8)
    }
    
    var animation: some View {
        ZStack {
            animationVM?.view()
                .frame(width: 280, height: 280)
            
            animationText
                .offset(y: 50)
        }
    }
    
    var animationText: some View {
        Text(NSLocalizedString("transactionSuccessful", comment: ""))
            .foregroundStyle(LinearGradient.primaryGradient)
            .font(.body18BrockmannMedium)
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
                .stroke(Color.blue400, lineWidth: 1)
        )
    }
}
