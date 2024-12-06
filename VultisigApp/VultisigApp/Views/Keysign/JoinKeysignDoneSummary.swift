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
            getGeneralCell(title: "action", description: getAction())
            Separator()
            getGeneralCell(title: "provider", description: getProvider())
            Separator()
            getGeneralCell(title: "swapFrom", description: getFromAmount())
            Separator()
            getGeneralCell(title: "to", description: getToAmount())
            
            if showApprove {
                Separator()
                getGeneralCell(title: "allowanceSpender", description: getSpender())
                Separator()
                getGeneralCell(title: "allowanceAmount", description: getAmount())
            }
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
            
            
            if let memo = viewModel.keysignPayload?.memo {
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
            
            link
        }
    }
    
    var link: some View {
        VStack {
            if viewModel.txid == viewModel.txid, let link = viewModel.getSwapProgressURL(txid: viewModel.txid) {
                Separator()
                
                HStack {
                    Spacer()
                    progressLink(link: link)
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
    
    private func progressLink(link: String) -> some View {
        Button {
            progressLink(link: link)
        } label: {
            Text(NSLocalizedString(viewModel.keysignPayload?.swapPayload != nil ? "swapTrackingLink" : "transactionTrackingLink", comment: ""))
                .font(.body14MontserratBold)
                .foregroundColor(.turquoise600)
                .underline()
        }
    }
    
    func getAction() -> String {
        guard viewModel.keysignPayload?.approvePayload == nil else {
            return NSLocalizedString("Approve and Swap", comment: "")
        }
        return NSLocalizedString("Swap", comment: "")
    }

    func getProvider() -> String {
        switch viewModel.keysignPayload?.swapPayload {
        case .oneInch:
            return "1Inch"
        case .thorchain:
            return "THORChain"
        case .mayachain:
            return "Maya protocol"
        case .none:
            return .empty
        }
    }

    var showApprove: Bool {
        viewModel.keysignPayload?.approvePayload != nil
    }

    func getSpender() -> String {
        return viewModel.keysignPayload?.approvePayload?.spender ?? .empty
    }

    func getAmount() -> String {
        guard let fromCoin = viewModel.keysignPayload?.coin, let amount = viewModel.keysignPayload?.approvePayload?.amount else {
            return .empty
        }

        return "\(String(describing: fromCoin.decimal(for: amount)).formatCurrencyWithSeparators(settingsViewModel.selectedCurrency)) \(fromCoin.ticker)"
    }

    func getFromAmount() -> String {
        guard let payload = viewModel.keysignPayload?.swapPayload else { return .empty }
        let amount = payload.fromCoin.decimal(for: payload.fromAmount)
        if payload.fromCoin.chain == payload.toCoin.chain {
            return "\(String(describing: amount).formatCurrencyWithSeparators(settingsViewModel.selectedCurrency)) \(payload.fromCoin.ticker)"
        } else {
            return "\(String(describing: amount).formatCurrencyWithSeparators(settingsViewModel.selectedCurrency)) \(payload.fromCoin.ticker) (\(payload.fromCoin.chain.ticker))"
        }
    }

    func getToAmount() -> String {
        guard let payload = viewModel.keysignPayload?.swapPayload else { return .empty }
        let amount = payload.toAmountDecimal
        if payload.fromCoin.chain == payload.toCoin.chain {
            return "\(String(describing: amount).formatCurrencyWithSeparators(settingsViewModel.selectedCurrency)) \(payload.toCoin.ticker)"
        } else {
            return "\(String(describing: amount).formatCurrencyWithSeparators(settingsViewModel.selectedCurrency)) \(payload.toCoin.ticker) (\(payload.toCoin.chain.ticker))"
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
