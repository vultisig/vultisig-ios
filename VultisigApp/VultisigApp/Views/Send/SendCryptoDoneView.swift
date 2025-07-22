//
//  SendCryptoDoneView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-17.
//

import SwiftUI
import RiveRuntime

struct SendCryptoDoneView: View {
    let vault: Vault
    let hash: String
    let approveHash: String?
    let chain: Chain

    var progressLink: String? = nil
    
    let sendTransaction: SendTransaction?
    let swapTransaction: SwapTransaction?
    
    @StateObject private var sendSummaryViewModel = SendSummaryViewModel()
    @StateObject private var swapSummaryViewModel = SwapCryptoViewModel()

    @State var showAlert = false
    @State var alertTitle = "hashCopied"
    @State var navigateToHome = false
    
    @State var animationVM: RiveViewModel? = nil
    
    @Environment(\.openURL) var openURL
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Background()
            view
            PopupCapsule(text: alertTitle, showPopup: $showAlert)
        }
        .navigationDestination(isPresented: $navigateToHome) {
            HomeView(selectedVault: vault)
        }
        .onAppear {
            animationVM = RiveViewModel(fileName: "vaultCreatedAnimation", autoPlay: true)
        }
    }
    
    var sendView: some View {
        VStack {
            sendContent
            continueButton
        }
    }
    
    var sendContent: some View {
        ScrollView {
            VStack {
                animation
                getAssetCard(coin: sendTransaction?.coin, title: "\(sendTransaction?.amount ?? "") \(sendTransaction?.coin.ticker ?? "")", description: sendTransaction?.amountInFiat)
                
                NavigationLink {
                    SendCryptoSecondaryDoneView(sendTransaction: sendTransaction, hash: hash, explorerLink: explorerLink())
                } label: {
                    transactionDetails
                }
            }
            .padding(24)
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

    var continueButton: some View {
        PrimaryButton(title: "done") {
            if let send = sendTransaction {
                send.reset(coin: send.coin)
            }
            navigateToHome = true
        }
        .padding(24)
    }

    var summaryCard: some View {
        SendCryptoDoneSummary(
            sendTransaction: sendTransaction,
            swapTransaction: swapTransaction,
            vault: vault,
            hash: hash,
            approveHash: approveHash,
            sendSummaryViewModel: sendSummaryViewModel,
            swapSummaryViewModel: swapSummaryViewModel
        )
    }
    
    var view: some View {
        ZStack {
            if let tx = swapTransaction {
                getSwapDoneView(tx)
            } else {
                sendView
            }
        }
    }
    
    private func getSwapDoneView(_ tx: SwapTransaction) -> some View {
        SwapCryptoDoneView(
            tx: tx,
            vault: vault,
            hash: hash,
            approveHash: approveHash,
            progressLink: progressLink,
            sendSummaryViewModel: sendSummaryViewModel,
            swapSummaryViewModel: swapSummaryViewModel,
            showAlert: $showAlert,
            alertTitle: $alertTitle,
            navigateToHome: $navigateToHome
        )
    }

    func explorerLink() -> String {
        return Endpoint.getExplorerURL(chain: chain, txid: hash)
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
        vault:Vault.example,
        hash: "bc1psrjtwm7682v6nhx2uwfgcfelrennd7pcvqq7v6w",
        approveHash: "123bc1psrjtwm7682v6nhx2uwfgcfelrennd7pcvqq7",
        chain: .thorChain,
        progressLink: "https://blockstream.info/tx/",
        sendTransaction: nil,
        swapTransaction: SwapTransaction()
    )
    .environmentObject(SettingsViewModel())
}
