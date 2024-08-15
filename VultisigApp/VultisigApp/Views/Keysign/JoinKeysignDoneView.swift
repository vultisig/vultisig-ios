//
//  JoinKeysignDoneView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-22.
//

import SwiftUI

struct JoinKeysignDoneView: View {
    let vault: Vault
    @ObservedObject var viewModel: KeysignViewModel
    @Binding var showAlert: Bool
    
    @Environment(\.openURL) var openURL
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        view
            .redacted(reason: viewModel.txid.isEmpty ? .placeholder : [])
    }
    
    var view: some View {
        VStack(spacing: 32) {
            header
            cards
            continueButton
        }
    }
    
    var cards: some View {
        ScrollView {
            if viewModel.txid.isEmpty {
                transactionComplete
            } else {
                if let approveTxid = viewModel.approveTxid {
                    card(title: NSLocalizedString("Approve", comment: ""), txid: approveTxid)
                }

                card(title: NSLocalizedString("transaction", comment: "Transaction"), txid: viewModel.txid)
            }
        }
    }

    func card(title: String, txid: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            titleSection(title: title, txid: txid)

            Text(txid)
                .font(.body13Menlo)
                .foregroundColor(.turquoise600)

            if viewModel.txid == txid, let link = viewModel.getSwapProgressURL(txid: viewModel.txid) {
                HStack {
                    Spacer()
                    progressButton(link: link)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }
    
    var transactionComplete: some View {
        Text(NSLocalizedString("transactionComplete", comment: "Transaction"))
            .font(.body24MontserratMedium)
            .foregroundColor(.neutral0)
    }
    
    func titleSection(title: String, txid: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body20MontserratSemiBold)
                .foregroundColor(.neutral0)
            
            copyButton(txid: txid)
            linkButton(txid: txid)
        }
    }
    
    func copyButton(txid: String) -> some View {
        Button {
            copyHash(txid: txid)
        } label: {
            Image(systemName: "square.on.square")
                .font(.body18Menlo)
                .foregroundColor(.neutral0)
        }
        
    }
    
    func linkButton(txid: String) -> some View {
        Button {
            shareLink(txid: txid)
        } label: {
            Image(systemName: "link")
                .font(.body18Menlo)
                .foregroundColor(.neutral0)
        }
        
    }

    func progressButton(link: String) -> some View {
        Button {
            progressLink(link: link)
        } label: {
            Text(NSLocalizedString("Swap progress", comment: ""))
                .font(.body14Menlo)
                .foregroundColor(.neutral0)
        }
    }

    var continueButton: some View {
        NavigationLink(destination: {
            HomeView(selectedVault: vault, showVaultsList: false)
        }, label: {
            FilledButton(title: "DONE")
        })
        .id(UUID())
        .padding(20)
    }
    
    var header: some View {
        Text(NSLocalizedString("transactionComplete", comment: ""))
            .font(.body)
            .bold()
            .foregroundColor(.neutral0)
    }
    
    private func copyHash(txid: String) {
        let urlStr = viewModel.getTransactionExplorerURL(txid: txid)
        showAlert = true
#if os(iOS)
        let pasteboard = UIPasteboard.general
        pasteboard.string = urlStr
#endif
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
        JoinKeysignDoneView(vault: Vault.example, viewModel: KeysignViewModel(), showAlert: .constant(false))
    }
}
