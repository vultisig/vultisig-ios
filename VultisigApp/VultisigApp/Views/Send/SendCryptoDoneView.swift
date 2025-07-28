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
    
    func sendView(tx: SendTransaction) -> some View {
        VStack {
            sendContent(tx: tx)
            continueButton
        }
    }
    
    func sendContent(tx: SendTransaction) -> some View {
        SendCryptoDoneContentView(
            input: SendCryptoContent(
                coin: tx.coin,
                amountCrypto: "\(tx.amount) \(tx.coin.ticker)",
                amountFiat: tx.amountInFiat,
                hash: hash,
                explorerLink: explorerLink(),
                memo: tx.memo,
                fromAddress: tx.fromAddress,
                toAddress: tx.toAddress,
                fee: (tx.gasInReadable, sendSummaryViewModel.feesInReadable(tx: tx, vault: vault))
            ),
            showAlert: $showAlert
        ) {
            tx.reset(coin: tx.coin)
        }
        .padding(.horizontal, 16)
    }

    var continueButton: some View {
        PrimaryButton(title: "done") {
            if let send = sendTransaction {
                send.reset(coin: send.coin)
            }
            navigateToHome = true
        }
        .padding(16)
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
            } else if let sendTransaction {
                sendView(tx: sendTransaction)
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
