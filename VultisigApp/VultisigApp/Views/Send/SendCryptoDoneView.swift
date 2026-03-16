//
//  SendCryptoDoneView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-17.
//

import SwiftData
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

    @Query private var vaults: [Vault]
    @Query private var addressBookItems: [AddressBookItem]

    @StateObject private var sendSummaryViewModel = SendSummaryViewModel()
    @StateObject private var swapSummaryViewModel = SwapCryptoViewModel()

    @State private var showAlert = false
    @State private var alertTitle = "hashCopied"

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

    private var toVaultName: String? {
        guard let tx = sendTransaction else { return nil }
        let chain = tx.coin.chain
        let address = tx.toAddress
        return vaults.first { v in v.coins.contains { coin in coin.chain == chain && coin.address == address } }?.name
    }

    private var toAddressBookTitle: String? {
        guard let tx = sendTransaction else { return nil }
        let txChainType = AddressBookChainType(coinMeta: tx.coin.toCoinMeta())
        let address = tx.toAddress.lowercased()
        return addressBookItems.first { item in
            AddressBookChainType(coinMeta: item.coinMeta) == txChainType &&
            item.address.lowercased() == address
        }?.title
    }

    private var toAddressLabel: String? { sendTransaction?.toAddressLabel }

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
                toVaultName: toVaultName,
                toAddressBookTitle: toAddressBookTitle,
                toAddressLabel: toAddressLabel,
                fee: FeeDisplay(crypto: tx.gasInReadable, fiat: sendSummaryViewModel.feesInReadable(tx: tx, vault: vault)),
                keysignPayload: keysignPayload,
                pubKeyECDSA: vault.pubKeyECDSA
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
