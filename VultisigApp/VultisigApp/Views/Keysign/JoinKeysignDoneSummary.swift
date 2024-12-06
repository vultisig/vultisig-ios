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
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    let summaryViewModel = JoinKeysignSummaryViewModel()
    
    var showApprove: Bool {
        viewModel.keysignPayload?.approvePayload != nil
    }
    
    var body: some View {
        ScrollView {
            ZStack {
                if viewModel.txid.isEmpty {
                    transactionComplete
                } else {
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
            
            card(title: NSLocalizedString("transaction", comment: "Transaction"), txid: viewModel.txid)
                .padding(.horizontal, -16)
            
            content
        }
        .padding(.vertical, 12)
        .background(Color.blue600)
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }
    
    var transactionComplete: some View {
        Text(NSLocalizedString("transactionComplete", comment: "Transaction"))
            .font(.body24MontserratMedium)
            .foregroundColor(.neutral0)
    }
    
    var content: some View {
        ZStack {
            if viewModel.keysignPayload?.swapPayload != nil {
                swapContent
            } else {
                transactionContent
            }
        }
        .padding(.horizontal, 16)
    }
    
    var swapContent: some View {
        VStack(spacing: 18) {
            Separator()
            getGeneralCell(
                title: "action",
                description: summaryViewModel.getAction(viewModel.keysignPayload)
            )
            
            Separator()
            getGeneralCell(
                title: "provider",
                description: summaryViewModel.getProvider(viewModel.keysignPayload)
            )
            
            Separator()
            getGeneralCell(
                title: "swapFrom",
                description: summaryViewModel.getFromAmount(
                    viewModel.keysignPayload,
                    selectedCurrency: settingsViewModel.selectedCurrency
                )
            )
            
            Separator()
            getGeneralCell(
                title: "to",
                description: summaryViewModel.getToAmount(
                    viewModel.keysignPayload,
                    selectedCurrency: settingsViewModel.selectedCurrency
                )
            )
            
            if showApprove {
                Separator()
                getGeneralCell(
                    title: "allowanceSpender",
                    description: summaryViewModel.getSpender(viewModel.keysignPayload)
                )
                
                Separator()
                getGeneralCell(
                    title: "allowanceAmount",
                    description: summaryViewModel.getAmount(
                        viewModel.keysignPayload,
                        selectedCurrency: settingsViewModel.selectedCurrency
                    )
                )
            }
            
            transactionLink
        }
    }
    
    var transactionContent: some View {
        VStack(spacing: 18) {
            Separator()
            getGeneralCell(
                title: "to",
                description: viewModel.keysignPayload?.toAddress ?? "",
                isVerticalStacked: true
            )
            
            
            if let memo = viewModel.keysignPayload?.memo, !memo.isEmpty {
                Separator()
                getGeneralCell(
                    title: "memo",
                    description: memo,
                    isVerticalStacked: false
                )
            }
            
            Separator()
            getGeneralCell(
                title: "amount",
                description: viewModel.keysignPayload?.toAmountString ?? "",
                isVerticalStacked: false
            )
            
            Separator()
            getGeneralCell(
                title: "value",
                description: viewModel.keysignPayload?.toAmountFiatString ?? "",
                isVerticalStacked: false
            )
            
            transactionLink
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
    
    var swapLink: some View {
        VStack {
            if let link = viewModel.getSwapProgressURL(txid: viewModel.txid) {
                Separator()
                
                HStack {
                    Spacer()
                    progressLink(txid: link)
                }
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
    
    private func titleSection(title: String, txid: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body20MontserratSemiBold)
                .foregroundColor(.neutral0)
            
            copyButton(txid: txid)
            linkButton(txid: txid)
        }
    }
    
    private func progressButton(link: String) -> some View {
        Button {
            progressLink(link: link)
        } label: {
            Text(NSLocalizedString("Swap progress", comment: ""))
                .font(.body14Menlo)
                .foregroundColor(.neutral0)
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
            shareLink(txid: txid)
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
        JoinKeysignDoneSummary(viewModel: KeysignViewModel(), showAlert: .constant(false))
    }
    .environmentObject(SettingsViewModel())
}
