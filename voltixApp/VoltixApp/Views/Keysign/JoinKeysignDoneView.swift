//
//  JoinKeysignDoneView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-22.
//

import SwiftUI

struct JoinKeysignDoneView: View {
    @Environment(\.openURL) var openURL
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: KeysignViewModel
    @State var showAlert = false
    
    var body: some View {
        view
            .redacted(reason: viewModel.txid.isEmpty ? .placeholder : [])
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(NSLocalizedString("hashCopied", comment: "")),
                    message: Text(viewModel.txid),
                    dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
                )
            }
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
                card
            }
        }
    }
    
    var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleSection
            
            Text(viewModel.txid)
                .font(.body13Menlo)
                .foregroundColor(.turquoise600)

            if viewModel.showSwapProgress {
                HStack {
                    Spacer()
                    progressbutton
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
    
    var titleSection: some View {
        HStack(spacing: 12) {
            Text(NSLocalizedString("transaction", comment: "Transaction"))
                .font(.body20MontserratSemiBold)
                .foregroundColor(.neutral0)
            
            copyButton
            linkButton
        }
    }
    
    var copyButton: some View {
        Button {
            copyHash()
        } label: {
            Image(systemName: "square.on.square")
                .font(.body18Menlo)
                .foregroundColor(.neutral0)
        }
        
    }
    
    var linkButton: some View {
        Button {
            shareLink()
        } label: {
            Image(systemName: "link")
                .font(.body18Menlo)
                .foregroundColor(.neutral0)
        }
        
    }

    var progressbutton: some View {
        Button {
            progressLink()
        } label: {
            Text(NSLocalizedString("Swap progress", comment: ""))
                .font(.body14Menlo)
                .foregroundColor(.neutral0)
        }
    }

    var continueButton: some View {
        NavigationLink(destination: {
            HomeView()
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
    
    private func copyHash() {
        showAlert = true
        let pasteboard = UIPasteboard.general
        pasteboard.string = viewModel.txid
    }
    
    private func shareLink() {
        let urlStr = viewModel.getTransactionExplorerURL(txid: viewModel.txid)
        if !urlStr.isEmpty, let url = URL(string:urlStr) {
            openURL(url)
        }
    }

    private func progressLink() {
        let urlStr = viewModel.getSwapProgressURL(txid: viewModel.txid)
        if !urlStr.isEmpty, let url = URL(string:urlStr) {
            openURL(url)
        }
    }
}

#Preview {
    ZStack {
        Background()
        JoinKeysignDoneView(viewModel: KeysignViewModel())
    }
}
