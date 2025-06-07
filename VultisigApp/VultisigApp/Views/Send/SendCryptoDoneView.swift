//
//  SendCryptoDoneView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-17.
//

import SwiftUI

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
    }
    
    var sendView: some View {
        VStack {
            cards
            continueButton
        }
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
            FilledButton(title: "complete")
        }
        .padding(40)
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
