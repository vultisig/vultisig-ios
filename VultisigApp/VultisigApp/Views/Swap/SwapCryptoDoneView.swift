//
//  SwapCryptoDoneView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-04.
//

import SwiftUI
import RiveRuntime

struct SwapCryptoDoneView: View {
    let tx: SwapTransaction
    let vault: Vault
    let hash: String
    let approveHash: String?
    let progressLink: String?
    let sendSummaryViewModel: SendSummaryViewModel
    let swapSummaryViewModel: SwapCryptoViewModel
    @Binding var showAlert: Bool
    @Binding var alertTitle: String
    @Binding var navigateToHome: Bool
    
    @State var showFees: Bool = false
    @State var animationVM: RiveViewModel? = nil
    
    @Environment(\.openURL) var openURL
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            cards
            buttons
        }
        .buttonStyle(BorderlessButtonStyle())
        .onAppear {
            animationVM = RiveViewModel(fileName: "vaultCreatedAnimation", autoPlay: true)
        }
    }
    
    var cards: some View {
        ScrollView {
            VStack {
                animation
                fromToCards
                summary
            }
            .padding(.horizontal)
        }
    }
    
    var trackButton: some View {
        PrimaryButton(title: "track", type: .secondary) {
            if let progressLink, let url = URL(string: progressLink) {
                openURL(url)
            }
        }
    }
    
    var doneButton: some View {
        PrimaryButton(title: "done") {
            navigateToHome = true
        }
    }
    
    var animation: some View {
        ZStack {
            animationVM?.view()
                .frame(width: 280, height: 280)
            
            animationText
                .offset(y: 50)
        }
    }
    
    var animationText: some View {
        Text(NSLocalizedString("transactionSuccessful", comment: ""))
            .foregroundStyle(LinearGradient.primaryGradient)
            .font(Theme.fonts.bodyLMedium)
    }
    
    var fromToCards: some View {
        ZStack {
            HStack(spacing: 8) {
                getFromToCard(
                    coin: tx.fromCoin,
                    title: sendSummaryViewModel.getFromAmount(
                        tx,
                        selectedCurrency: settingsViewModel.selectedCurrency
                    ),
                    description: swapSummaryViewModel.fromFiatAmount(tx: tx),
                    isFrom: true
                )
                
                getFromToCard(
                    coin: tx.toCoin,
                    title: sendSummaryViewModel.getToAmount(
                        tx,
                        selectedCurrency: settingsViewModel.selectedCurrency
                    ),
                    description: swapSummaryViewModel.toFiatAmount(tx: tx),
                    isFrom: false
                )
            }
            
            chevronContent
        }
    }
    
    var chevronContent: some View {
        ZStack {
            chevronIcon
            
            filler
                .offset(y: -24)
            
            filler
                .offset(y: 24)
            
        }
    }
    
    var chevronIcon: some View {
        Image(systemName: "chevron.right")
            .foregroundColor(Theme.colors.textButtonDisabled)
            .font(Theme.fonts.caption12)
            .bold()
            .frame(width: 24, height: 24)
            .background(Theme.colors.bgSecondary)
            .cornerRadius(60)
            .padding(8)
            .background(Theme.colors.bgPrimary)
            .cornerRadius(60)
            .overlay(
                Circle()
                    .stroke(Theme.colors.border, lineWidth: 1)
            )
    }
    
    var filler: some View {
        Rectangle()
            .frame(width: 6, height: 18)
            .foregroundColor(Theme.colors.bgPrimary)
    }
    
    var summary: some View {
        VStack(spacing: 0) {
            getCell(
                title: "swapTXHash",
                value: hash,
                valueMaxWidth: 120,
                showCopyButton: true
            )
            
            if let approveHash {
                separator
                getCell(
                    title: "approvalTXHash",
                    value: approveHash,
                    valueMaxWidth: 120,
                    showCopyButton: true
                )
            }
            
            separator
            getCell(
                title: "from",
                value: vault.name,
                bracketValue: tx.fromCoin.address,
                bracketMaxWidth: 120
            )
            
            separator
            getCell(
                title: "to",
                value: tx.toCoin.address,
                valueMaxWidth: 120
            )
            
            if swapSummaryViewModel.showTotalFees(tx: tx) {
                separator
                totalFees
            }
            
            otherFees
        }
        .padding(.horizontal, 24)
        .background(Theme.colors.bgSecondary)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }
    
    var separator: some View {
        Separator()
            .opacity(0.2)
    }
    
    var totalFees: some View {
        Button {
            showFees.toggle()
        } label: {
            totalFeesLabel
        }
    }
    
    var totalFeesLabel: some View {
        HStack {
            getCell(
                title: "totalFee",
                value: "\(swapSummaryViewModel.totalFeeString(tx: tx))"
            )
            
            chevron
        }
    }
    
    var chevron: some View {
        Image(systemName: "chevron.up")
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textPrimary)
            .rotationEffect(Angle(degrees: showFees ? 0 : 180))
    }
    
    var otherFees: some View {
        HStack {
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Theme.colors.primaryAccent4)
            
            expandableFees
        }
        .frame(maxHeight: showFees ? nil : 0)
        .clipped()
    }
    
    var expandableFees: some View {
        VStack(spacing: 4) {
            if swapSummaryViewModel.showFees(tx: tx) {
                swapFees
            }
            
            if swapSummaryViewModel.showGas(tx: tx) {
                swapGas
            }
        }
    }
    
    var swapFees: some View {
        getCell(
            title: "swapFee",
            value: swapSummaryViewModel.swapFeeString(tx: tx)
        )
    }
    
    var swapGas: some View {
        getCell(
            title: "networkFee",
            value: "\(swapSummaryViewModel.swapGasString(tx: tx))(\(swapSummaryViewModel.approveFeeString(tx: tx)))"
        )
    }
    
    private func getFromToCard(coin: Coin, title: String, description: String, isFrom: Bool) -> some View {
        VStack(spacing: 8) {
            Text(isFrom ? "from".localized : "to".localized)
                .foregroundStyle(Theme.colors.textExtraLight)
                .font(Theme.fonts.caption10)
            
            AsyncImageView(
                logo: coin.logo,
                size: CGSize(width: 32, height: 32),
                ticker: coin.ticker,
                tokenChainLogo: coin.tokenChainLogo
            )
            .padding(.bottom, 8)
            
            VStack(spacing: 4) {
                Text(title)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundColor(Theme.colors.textPrimary)
                
                Text(description.formatToFiat(includeCurrencySymbol: true))
                    .font(Theme.fonts.caption10)
                    .foregroundColor(Theme.colors.textExtraLight)
            }
        }
        .frame(height: 130)
        .frame(maxWidth: .infinity)
        .background(Theme.colors.bgSecondary)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }
    
    private func getCell(
        title: String,
        value: String,
        bracketValue: String? = nil,
        valueMaxWidth: CGFloat? = nil,
        bracketMaxWidth: CGFloat? = nil,
        showCopyButton: Bool = false
    ) -> some View {
        HStack {
            Text(NSLocalizedString(title, comment: ""))
                .foregroundColor(Theme.colors.textExtraLight)
            
            Spacer()
            
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(Theme.colors.textPrimary)
                .frame(maxWidth: valueMaxWidth, alignment: .trailing)
            
            if let bracketValue {
                Group {
                    Text("(") +
                    Text(bracketValue) +
                    Text(")")
                }
                .foregroundColor(Theme.colors.textExtraLight)
                .frame(maxWidth: bracketMaxWidth)
                .truncationMode(.middle)
                .lineLimit(1)
            }
            
            if showCopyButton {
                getCopyButton(for: value)
            }
        }
        .padding(.vertical)
        .font(Theme.fonts.bodySMedium)
    }
    
    private func getCopyButton(for value: String) -> some View {
        Button {
            copyValue(value)
        } label: {
            Image(systemName: "doc.on.clipboard")
                .foregroundColor(Theme.colors.textPrimary)
                .font(Theme.fonts.bodySMedium)
        }
    }
}

#Preview {
    SwapCryptoDoneView(
        tx: SwapTransaction(),
        vault:Vault.example,
        hash: "bc1psrjtwm7682v6nhx2uwfgcfelrennd7pcvqq7v6w",
        approveHash: "123bc1psrjtwm7682v6nhx2uwfgcfelrennd7pcvqq7",
        progressLink: nil,
        sendSummaryViewModel: SendSummaryViewModel(),
        swapSummaryViewModel: SwapCryptoViewModel(),
        showAlert: .constant(false),
        alertTitle: .constant(""),
        navigateToHome: .constant(false)
    )
    .environmentObject(SettingsViewModel())
}
