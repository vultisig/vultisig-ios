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
//            cards
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
                    SendCryptoSecondaryDoneView(sendTransaction: sendTransaction, hash: hash, explorerLink: explorerLink(hash: hash))
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
    
    var cards: some View {
        ScrollView {
            if let approveHash {
                card(title: NSLocalizedString("Approve", comment: ""), hash: approveHash)
            }

            transactionCard
        }
    }
    
    var transactionCard: some View {
        VStack(spacing: 0) {
            card(title: NSLocalizedString("transaction", comment: "Transaction"), hash: hash)
                .padding(.horizontal, -16)
            
            summaryCard
            
            if progressLink != nil, hash == self.hash {
                Separator()
                    .padding(.horizontal, 16)
                
                HStack {
                    Spacer()
                    progressbutton
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }
    
    var progressbutton: some View {
        Button {
            checkProgressLink()
        } label: {
            Text(NSLocalizedString(swapTransaction != nil ? "swapTrackingLink" : "transactionTrackingLink", comment: ""))
                .font(.body14MontserratBold)
                .foregroundColor(.turquoise600)
                .underline()
        }
    }

    var continueButton: some View {
        Button {
            if let send = sendTransaction {
                send.reset(coin: send.coin)
            }
            navigateToHome = true
        } label: {
            FilledButton(title: "done", textColor: .neutral0, background: .persianBlue400)
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
    
    func card(title: String, hash: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            titleSection(title: title, hash: hash)

            Text(hash)
                .font(.body13Menlo)
                .foregroundColor(.turquoise600)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }
    
    func titleSection(title: String, hash: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body20MontserratSemiBold)
                .foregroundColor(.neutral0)
            
            copyButton(hash: hash)
            linkButton(hash: hash)
        }
    }
    
    func copyButton(hash: String) -> some View {
        Button {
            copyHash(hash: hash)
        } label: {
            Image(systemName: "square.on.square")
                .font(.body18Menlo)
                .foregroundColor(.neutral0)
        }
        
    }
    
    func linkButton(hash: String) -> some View {
        Button {
            shareLink(hash: hash)
        } label: {
            Image(systemName: "link")
                .font(.body18Menlo)
                .foregroundColor(.neutral0)
        }
    }

    func explorerLink(hash: String) -> String {
        return Endpoint.getExplorerURL(chain: chain, txid: hash)
    }
    
    private func shareLink(hash: String) {
        let explorerLink = explorerLink(hash: hash)
        if !explorerLink.isEmpty, let url = URL(string: explorerLink) {
            openURL(url)
        }
    }

    private func checkProgressLink() {
        if let progressLink, let url = URL(string: progressLink) {
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
