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

    @State var showAlert = false
    
    @Environment(\.openURL) var openURL
    @Environment(\.dismiss) var dismiss
    
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    var showProgress: Bool {
        return progressLink != nil
    }
    
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

            transactionCard
        }
    }
    
    var transactionCard: some View {
        VStack(spacing: 0) {
            card(title: NSLocalizedString("transaction", comment: "Transaction"), hash: hash)
                .padding(.horizontal, -16)
            
            summaryCard
            
            if showProgress, hash == self.hash {
                Separator()
                HStack {
                    Spacer()
                    progressbutton
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }
    
    var progressbutton: some View {
        Button {
            checkProgressLink()
        } label: {
            Text(NSLocalizedString("swapTrackingLink", comment: ""))
                .font(.body14MontserratBold)
                .foregroundColor(.turquoise600)
                .underline()
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
    
    var summaryCard: some View {
        ZStack {
            if let tx = sendTransaction {
                getSendCard(tx)
            } else if let tx = swapTransaction {
                getSwapCard(tx)
            }
        }
        .padding(.horizontal, 16)
    }
    
    func getSendCard(_ tx: SendTransaction) -> some View {
        VStack(spacing: 18) {
            Separator()
            getGeneralCell(title: "from", description: tx.fromAddress, isVerticalStacked: true)
            Separator()
            getGeneralCell(title: "to", description: tx.toAddress, isVerticalStacked: true)
            Separator()
            getGeneralCell(title: "networkFee", description: tx.gasInReadable)
        }
    }
    
    func getSwapCard(_ tx: SwapTransaction) -> some View {
        VStack(spacing: 18) {
            Separator()
            getGeneralCell(title: "from", description: getFromAmount(tx))
            Separator()
            getGeneralCell(title: "to", description: getToAmount(tx))
            Separator()
            getGeneralCell(title: "networkFee", description: swapFeeString(tx))
        }
    }
    
    func getGeneralCell(title: String, description: String, isVerticalStacked: Bool = false) -> some View {
        ZStack {
            if isVerticalStacked {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString(title, comment: ""))
                    Text(description)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    Text(NSLocalizedString(title, comment: ""))
                    Spacer()
                    Text(description)
                }
            }
        }
        .font(.body16MenloBold)
        .foregroundColor(.neutral100)
    }
    
    func card(title: String, hash: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            titleSection(title: title, hash: hash)

            Text(hash)
                .font(.body13Menlo)
                .foregroundColor(.turquoise600)
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

    func explorerLink(hash: String) -> String {
        return Endpoint.getExplorerURL(chainTicker: chain.ticker, txid: hash)
    }
    
    func getFromAmount(_ tx: SwapTransaction) -> String {
        if tx.fromCoin.chain == tx.toCoin.chain {
            return "\(tx.fromAmount.formatCurrencyWithSeparators(settingsViewModel.selectedCurrency)) \(tx.fromCoin.ticker)"
        } else {
            return "\(tx.fromAmount.formatCurrencyWithSeparators(settingsViewModel.selectedCurrency)) \(tx.fromCoin.ticker) (\(tx.fromCoin.chain.ticker))"
        }
    }

    func getToAmount(_ tx: SwapTransaction) -> String {
        if tx.fromCoin.chain == tx.toCoin.chain {
            return "\(tx.toAmountDecimal.description.formatCurrencyWithSeparators(settingsViewModel.selectedCurrency)) \(tx.toCoin.ticker)"
        } else {
            return "\(tx.toAmountDecimal.description.formatCurrencyWithSeparators(settingsViewModel.selectedCurrency)) \(tx.toCoin.ticker) (\(tx.toCoin.chain.ticker))"
        }
    }
    
    func swapFeeString(_ tx: SwapTransaction) -> String {
        guard let inboundFeeDecimal = tx.inboundFeeDecimal else { return .empty }
        
        let fromCoin = feeCoin(tx: tx)
        let inboundFee = tx.toCoin.raw(for: inboundFeeDecimal)
        let fee = tx.toCoin.fiat(value: inboundFee) + fromCoin.fiat(value: tx.fee)
        return fee.formatToFiat(includeCurrencySymbol: true)
    }
    
    func feeCoin(tx: SwapTransaction) -> Coin {
        switch tx.fromCoin.chainType {
        case .UTXO, .Solana, .THORChain, .Cosmos, .Polkadot, .Sui, .Ton:
            return tx.fromCoin
        case .EVM:
            guard !tx.fromCoin.isNativeToken else { return tx.fromCoin }
            return tx.fromCoins.first(where: { $0.chain == tx.fromCoin.chain && $0.isNativeToken }) ?? tx.fromCoin
        }
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
        progressLink: "https://blockstream.info/tx/",
        sendTransaction: SendTransaction(),
        swapTransaction: SwapTransaction()
    )
    .environmentObject(SettingsViewModel())
}
