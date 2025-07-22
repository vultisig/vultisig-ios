//
//  JoinKeysignDoneSummary.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-12-05.
//

import SwiftUI

struct JoinKeysignDoneSummary: View {
    let vault: Vault
    let viewModel: KeysignViewModel
    @Binding var showAlert: Bool
    @Binding var moveToHome: Bool
    
    @Environment(\.openURL) var openURL
    
    let summaryViewModel = JoinKeysignSummaryViewModel()
    
    var body: some View {
        ZStack {
            if viewModel.keysignPayload?.swapPayload != nil {
                swapContent
            } else {
                ScrollView {
                    summary
                }
            }
        }
    }
    
    var summary: some View {
        VStack {
            if let approveTxid = viewModel.approveTxid {
                card(title: NSLocalizedString("Approve", comment: ""), txid: approveTxid)
            }
            
            if viewModel.customMessagePayload == nil {
                card(title: NSLocalizedString("transaction", comment: "Transaction"), txid: viewModel.txid)
                    .padding(.horizontal, -16)
            }
            
            content
        }
        .padding(.vertical, 12)
        .background(Color.blue600)
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }
    
    var content: some View {
        ZStack {
            if viewModel.customMessagePayload != nil {
                signMessageContent
            } else {
                transactionContent
            }
        }
        .padding(.horizontal, 16)
    }
    
    var swapContent: some View {
        JoinSwapDoneSummary(
            vault: vault,
            keysignViewModel: viewModel,
            summaryViewModel: summaryViewModel,
            moveToHome: $moveToHome,
            showAlert: $showAlert
        )
    }
    
    var transactionContent: some View {
        VStack(spacing: 18) {
            
            if let address = viewModel.keysignPayload?.toAddress, !address.isEmpty {
                
                Separator()
                getGeneralCell(
                    title: "to",
                    description: address,
                    isVerticalStacked: true
                )
                
            }
            
            if let memo = viewModel.keysignPayload?.memo, !memo.isEmpty {
                Separator()
                
                // Show decoded memo if available, otherwise show original memo
                if let decodedMemo = viewModel.decodedMemo, !decodedMemo.isEmpty {
                    getGeneralCell(
                        title: "action",
                        description: decodedMemo,
                        isVerticalStacked: false
                    )
                } else {
                    getGeneralCell(
                        title: "memo",
                        description: memo,
                        isVerticalStacked: false
                    )
                }
            }
            
            if let amount = viewModel.keysignPayload?.toAmountWithTickerString, !amount.isEmpty {
                
                Separator()
                getGeneralCell(
                    title: "amount",
                    description: amount,
                    isVerticalStacked: false
                )
                
            }
            
            if let fiat = viewModel.keysignPayload?.toAmountFiatString, !fiat.isEmpty {
                
                Separator()
                getGeneralCell(
                    title: "value",
                    description: fiat,
                    isVerticalStacked: false
                )
                
            }
            
            transactionLink
        }
    }
    
    var signMessageContent: some View {
        VStack(spacing: 18) {
            getGeneralCell(
                title: "Method",
                description: viewModel.customMessagePayload?.method ?? "",
                isVerticalStacked: true
            )
            
            Separator()
            // Show decoded message if available, otherwise show raw message
            if let decodedMessage = viewModel.customMessagePayload?.decodedMessage, !decodedMessage.isEmpty {
                getGeneralCell(
                    title: "Transaction Details",
                    description: decodedMessage,
                    isVerticalStacked: true
                )
            } else {
                getGeneralCell(
                    title: "Message",
                    description: viewModel.customMessagePayload?.message ?? "",
                    isVerticalStacked: true
                )
            }
            Separator()
            getGeneralCell(
                title: "Signature",
                description: viewModel.customMessageSignature(),
                isVerticalStacked: true
            )
        }
    }
    
    var transactionLink: some View {
        VStack {
            Separator()
            
            HStack {
                Spacer()
                progressLink(txid: viewModel.txid)
            }
        }
    }
    
    private func getGeneralCell(title: String, description: String, isVerticalStacked: Bool = false) -> some View {
        ZStack {
            if isVerticalStacked {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString(title, comment: ""))
                        .font(.body20MontserratSemiBold)
                    
                    Text(description)
                        .foregroundColor(.turquoise400)
                        .font(.body13MenloBold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    Text(NSLocalizedString(title, comment: ""))
                    
                    Spacer()
                    
                    Text(description)
                }
                .font(.body16MontserratBold)
            }
        }
        .foregroundColor(.neutral100)
    }
    
    private func card(title: String, txid: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            titleSection(title: title, txid: txid)
            
            Text(txid)
                .font(.body13Menlo)
                .foregroundColor(.turquoise600)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }
    
    private func titleSection(title: String, txid: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body20MontserratSemiBold)
                .foregroundColor(.neutral0)
            
            copyButton(txid: txid)
            linkButton(txid: txid)
        }
    }
    
    private func copyButton(txid: String) -> some View {
        Button {
            copyHash(txid: txid)
        } label: {
            Image(systemName: "square.on.square")
                .font(.body18Menlo)
                .foregroundColor(.neutral0)
        }
        
    }
    
    private func linkButton(txid: String) -> some View {
        Button {
            shareLink(txid: txid)
        } label: {
            Image(systemName: "link")
                .font(.body18Menlo)
                .foregroundColor(.neutral0)
        }
        
    }
    
    private func progressLink(txid: String) -> some View {
        Button {
            if let link = viewModel.getSwapProgressURL(txid: viewModel.txid) {
                progressLink(link: link)
            } else {
                shareLink(txid: txid)
            }
        } label: {
            Text(NSLocalizedString(viewModel.keysignPayload?.swapPayload != nil ? "swapTrackingLink" : "transactionTrackingLink", comment: ""))
                .font(.body14MontserratBold)
                .foregroundColor(.turquoise600)
                .underline()
                .padding(.vertical, 8)
        }
    }
    
    private func shareLink(txid: String) {
        let urlString = viewModel.getTransactionExplorerURL(txid: txid)
        if !urlString.isEmpty, let url = URL(string: urlString) {
            openURL(url)
        }
    }
    
    private func progressLink(link: String) {
        if !link.isEmpty, let url = URL(string: link) {
            openURL(url)
        }
    }
}

#Preview {
    ZStack {
        Background()
        JoinKeysignDoneSummary(vault: Vault.example, viewModel: KeysignViewModel(), showAlert: .constant(false), moveToHome: .constant(false))
    }
    .environmentObject(SettingsViewModel())
}
