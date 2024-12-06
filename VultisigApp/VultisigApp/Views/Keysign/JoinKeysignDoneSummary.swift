//
//  JoinKeysignDoneSummary.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-12-05.
//

import SwiftUI

struct JoinKeysignDoneSummary: View {
    let viewModel: KeysignViewModel
    @Binding var showAlert: Bool
    
    @Environment(\.openURL) var openURL
    
    var body: some View {
        ScrollView {
            ZStack {
                if viewModel.txid.isEmpty {
                    transactionComplete
                } else {
                    summary
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
    
    var summary: some View {
        VStack {
            if let approveTxid = viewModel.approveTxid {
                card(title: NSLocalizedString("Approve", comment: ""), txid: approveTxid)
            }
            
            card(title: NSLocalizedString("transaction", comment: "Transaction"), txid: viewModel.txid)
            
            content
        }
    }
    
    var transactionComplete: some View {
        Text(NSLocalizedString("transactionComplete", comment: "Transaction"))
            .font(.body24MontserratMedium)
            .foregroundColor(.neutral0)
    }
    
    var content: some View {
        ZStack {
            if viewModel.keysignPayload?.swapPayload != nil {
//                swapContent
            } else {
                transactionContent
            }
        }
    }
    
    var transactionContent: some View {
        VStack(spacing: 18) {
            Separator()
            getGeneralCell(
                title: "from",
                description: viewModel.keysignPayload?.toAddress ?? "",
                isVerticalStacked: true
            )
            
            
            if let memo = viewModel.keysignPayload?.memo {
                Separator()
                getGeneralCell(
                    title: "memo",
                    description: memo,
                    isVerticalStacked: true
                )
            }
            
            Separator()
            getGeneralCell(
                title: "amount",
                description: viewModel.keysignPayload?.toAmountString ?? "",
                isVerticalStacked: true
            )
        }
    }
    
    private func getGeneralCell(title: String, description: String, isVerticalStacked: Bool = false, isBold: Bool = true) -> some View {
        ZStack {
            if isVerticalStacked {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString(title, comment: ""))
                        .bold()
                    
                    Text(description)
                        .opacity(isBold ? 1 : 0.4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    Text(NSLocalizedString(title, comment: ""))
                        .bold()
                    
                    Spacer()
                    
                    Text(description)
                        .opacity(isBold ? 1 : 0.4)
                }
            }
        }
        .font(.body16Menlo)
        .foregroundColor(.neutral100)
        .bold(isBold)
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
    
    func titleSection(title: String, txid: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body20MontserratSemiBold)
                .foregroundColor(.neutral0)
            
            copyButton(txid: txid)
            linkButton(txid: txid)
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
    JoinKeysignDoneSummary(viewModel: KeysignViewModel(), showAlert: .constant(false))
}
