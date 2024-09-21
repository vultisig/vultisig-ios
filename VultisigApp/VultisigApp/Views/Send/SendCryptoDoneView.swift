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

    @State var showAlert = false
    
    @Environment(\.openURL) var openURL
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Background()
            view
            PopupCapsule(text: "urlCopied", showPopup: $showAlert)
        }
    }
    
    var cards: some View {
        ScrollView {
            if let approveHash {
                card(title: NSLocalizedString("Approve", comment: ""), hash: approveHash)
            }

            card(title: NSLocalizedString("transaction", comment: "Transaction"), hash: hash)
        }
    }
    
    func card(title: String, hash: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            titleSection(title: title, hash: hash)

            Text(hash)
                .font(.body13Menlo)
                .foregroundColor(.turquoise600)

            if showProgress, hash == self.hash {
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

    var progressbutton: some View {
        Button {
            checkProgressLink()
        } label: {
            Text(NSLocalizedString("swapProgress", comment: ""))
                .font(.body14Menlo)
                .foregroundColor(.turquoise600)
        }
    }

    var continueButton: some View {
        NavigationLink(destination: {
            HomeView(selectedVault: vault)
        }, label: {
            FilledButton(title: "complete")
        })
        .id(UUID())
        .padding(40)
    }

    var showProgress: Bool {
        return progressLink != nil
    }

    func explorerLink(hash: String) -> String {
        return Endpoint.getExplorerURL(chainTicker: chain.ticker, txid: hash)
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
        progressLink: "https://blockstream.info/tx/"
    )
    .previewDevice("iPhone 13 Pro")
}
