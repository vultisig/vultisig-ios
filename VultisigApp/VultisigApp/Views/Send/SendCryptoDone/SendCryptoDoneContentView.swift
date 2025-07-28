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
    @Binding var showAlert: Bool
    let onDone: () -> Void
    
    @State var animationVM: RiveViewModel? = nil
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                animation
                getAssetCard(
                    coin: input.coin,
                    title: input.amountCrypto,
                    description: input.amountFiat
                )
                
                VStack(spacing: 16) {
                    Group {
                        SendCryptoTransactionHashRowView(
                            hash: input.hash,
                            explorerLink: input.explorerLink,
                            showCopy: true,
                            showAlert: $showAlert
                        )
                        Separator()
                            .opacity(0.8)
                    }
                    .showIf(input.hash.isNotEmpty)
                    
                    transactionDetailsButton
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .foregroundColor(.lightText)
                .background(Color.blue600)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue400, lineWidth: 1)
                )
            }
        }
        .onLoad {
            animationVM = RiveViewModel(fileName: "vaultCreatedAnimation", autoPlay: true)
        }
    }
    
    var transactionDetailsButton: some View {
        NavigationLink {
            SendCryptoSecondaryDoneView(input: input) {
                onDone()
            }
        } label: {
            HStack {
                Text(NSLocalizedString("transactionDetails", comment: ""))
                Spacer()
                Image(systemName: "chevron.right")
            }
        }
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

#Preview {
    SendCryptoDoneView(
        vault: .example,
        hash: "294FF0BCDDA7E79140782FB3F5F759FFEE1C11639194FF500BAB6D92012C615C",
        approveHash: "",
        chain: .thorChain,
        sendTransaction: nil,
        swapTransaction: nil
    )
}
