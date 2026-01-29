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
    let isSend: Bool

    var progressLink: String? = nil

    let sendTransaction: SendTransaction?
    let swapTransaction: SwapTransaction?
    let keysignPayload: KeysignPayload?

    @StateObject private var sendSummaryViewModel = SendSummaryViewModel()
    @StateObject private var swapSummaryViewModel = SwapCryptoViewModel()

    @State var showAlert = false
    @State var alertTitle = "hashCopied"

    @Environment(\.openURL) var openURL
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appViewModel: AppViewModel

    init(
        vault: Vault,
        hash: String,
        approveHash: String?,
        chain: Chain,
        progressLink: String? = nil,
        sendTransaction: SendTransaction?,
        swapTransaction: SwapTransaction?,
        isSend: Bool,
        keysignPayload: KeysignPayload? = nil
    ) {
        self.vault = vault
        self.hash = hash
        self.approveHash = approveHash
        self.chain = chain
        self.progressLink = progressLink
        self.sendTransaction = sendTransaction
        self.swapTransaction = swapTransaction
        self.isSend = isSend
        self.keysignPayload = keysignPayload
    }

    var body: some View {
        ZStack {
            Background()
            view
        }
        .overlay(PopupCapsule(text: alertTitle, showPopup: $showAlert))
    }

    func sendView(tx: SendTransaction) -> some View {
        sendContent(tx: tx)
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
                isSend: isSend,
                fromAddress: tx.fromAddress,
                toAddress: tx.toAddress,
                fee: FeeDisplay(crypto: tx.gasInReadable, fiat: sendSummaryViewModel.feesInReadable(tx: tx, vault: vault)),
                keysignPayload: keysignPayload
            ),
            showAlert: $showAlert
        ) {
            if let send = sendTransaction {
                send.reset(coin: send.coin)
            }
        }
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
            alertTitle: $alertTitle
        )
    }

    func explorerLink() -> String {
        return Endpoint.getExplorerURL(chain: chain, txid: hash)
    }
}

#Preview {
    SendCryptoDoneView(
        vault: Vault.example,
        hash: "bc1psrjtwm7682v6nhx2uwfgcfelrennd7pcvqq7v6w",
        approveHash: "123bc1psrjtwm7682v6nhx2uwfgcfelrennd7pcvqq7",
        chain: .thorChain,
        progressLink: "https://blockstream.info/tx/",
        sendTransaction: SendTransaction(),
        swapTransaction: nil,
        isSend: true
    )
    .environmentObject(SettingsViewModel())
    .environmentObject(AppViewModel())
}
