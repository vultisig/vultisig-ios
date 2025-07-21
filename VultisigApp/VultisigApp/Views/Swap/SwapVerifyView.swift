//
//  SwapVerifyView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 08.04.2024.
//

import SwiftUI

struct SwapVerifyView: View {
    @StateObject var verifyViewModel = SwapCryptoVerifyViewModel()

    @ObservedObject var tx: SwapTransaction
    @ObservedObject var swapViewModel: SwapCryptoViewModel
    
    @StateObject var referredViewModel = ReferredViewModel()

    let vault: Vault

    @State var fastPasswordPresented = false
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Background()
            view
        }
        .onReceive(timer) { input in
            swapViewModel.updateTimer(tx: tx, vault: vault, referredCode: referredViewModel.savedReferredCode)
        }
        .onDisappear {
            swapViewModel.isLoading = false
        }
    }

    var view: some View {
        container
    }
    
    var content: some View {
        VStack(spacing: 16) {
            fields
            if tx.isFastVault {
                fastVaultButton
            }
            pairedSignButton
        }
    }

    var summary: some View {
        VStack(spacing: 16) {
            summaryTitle
            summaryFromToContent
            
            if let providerName = tx.quote?.displayName {
                separator
                getValueCell(
                    for: "provider",
                    with: providerName,
                    showIcon: true
                )
            }
            
            if swapViewModel.showGas(tx: tx) {
                separator
                getValueCell(
                    for: "networkFee",
                    with: swapViewModel.swapGasString(tx: tx),
                    bracketValue: swapViewModel.approveFeeString(tx: tx)
                )
            }
            
            if swapViewModel.showFees(tx: tx) {
                separator
                getValueCell(
                    for: "swapFee",
                    with: swapViewModel.swapGasString(tx: tx),
                    bracketValue: swapViewModel.swapFeeString(tx: tx)
                )
            }
            
            if swapViewModel.showTotalFees(tx: tx) {
                separator
                getValueCell(
                    for: "maxTotalFee",
                    with: swapViewModel.totalFeeString(tx: tx)
                )
            }
            
            separator
            getValueCell(
                for: "vault",
                with: vault.name
            )
        }
        .padding(16)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    var summaryFromToContent: some View {
        HStack {
            summaryFromToIcons
            summaryFromTo
        }
    }
    
    var summaryFromToIcons: some View {
        VStack(spacing: 0) {
            getCoinIcon(for: tx.fromCoin)
            verticalSeparator
            chevronIcon
            verticalSeparator
            getCoinIcon(for: tx.toCoin)
        }
    }
    
    var verticalSeparator: some View {
        Rectangle()
            .frame(width: 1, height: 12)
            .foregroundColor(.blue400)
    }
    
    var summaryFromTo: some View {
        VStack(spacing: 16) {
                        getSwapAssetCell(
                for: tx.fromAmountDecimal.formatForDisplay(),
                with: tx.fromCoin.ticker,
                on: tx.fromCoin.chain
            )
            
            separator
                .padding(.leading, 12)
            
                        getSwapAssetCell(
                for: tx.toAmountDecimal.formatForDisplay(),
                with: tx.toCoin.ticker,
                on: tx.toCoin.chain
            )
        }
    }
    
    var chevronIcon: some View {
        Image(systemName: "arrow.down")
            .font(.body12BrockmannMedium)
            .foregroundColor(.persianBlue200)
            .padding(6)
            .background(Color.blue400)
            .cornerRadius(32)
            .bold()
    }
    
    var summaryTitle: some View {
        Text(NSLocalizedString("youreSwapping", comment: ""))
            .font(.body14BrockmannMedium)
            .foregroundColor(.lightText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var checkboxes: some View {
        VStack(spacing: 16) {
            Checkbox(isChecked: $verifyViewModel.isAmountCorrect, text: "swapVerifyCheckbox1Description")
            Checkbox(isChecked: $verifyViewModel.isFeeCorrect, text: "swapVerifyCheckbox2Description")
            if showApproveCheckmark {
                Checkbox(isChecked: $verifyViewModel.isApproveCorrect, text: "swapVerifyCheckbox3Description")
            }
        }
    }

    var fastVaultButton: some View {
        Button {
            fastPasswordPresented = true
        } label: {
            FilledButton(title: NSLocalizedString("fastSign", comment: ""))
        }
        .disabled(!verifyViewModel.isValidForm(shouldApprove: tx.isApproveRequired))
        .opacity(verifyViewModel.isValidForm(shouldApprove: tx.isApproveRequired) ? 1 : 0.5)
        .padding(.horizontal, 24)
        .sheet(isPresented: $fastPasswordPresented) {
            FastVaultEnterPasswordView(
                password: $tx.fastVaultPassword,
                vault: vault, 
                onSubmit: { signPressed() }
            )
        }
    }

    var pairedSignButton: some View {
        let isDisabled = !verifyViewModel.isValidForm(shouldApprove: tx.isApproveRequired)
        
        return Button {
            signPressed()
        } label: {
            if swapViewModel.isLoadingTransaction {
                ButtonLoader()
            } else if tx.isFastVault {
                OutlineButton(title: "Paired sign")
                    .opacity(!isDisabled ? 1 : 0.5)
            } else {
                FilledButton(
                    title: "startTransaction",
                    textColor: isDisabled ? .textDisabled : .blue600,
                    background: isDisabled ? .buttonDisabled : .turquoise600
                )
            }
        }
        .disabled(isDisabled || swapViewModel.isLoadingTransaction)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    func signPressed() {
        Task {
            if await swapViewModel.buildSwapKeysignPayload(tx: tx, vault: vault) {
                swapViewModel.moveToNextView()
            }
        }
    }

    var showApproveCheckmark: Bool {
        return tx.isApproveRequired
    }
    
    var separator: some View {
        Separator()
            .opacity(0.2)
    }
    
    var refreshCounter: some View {
        SwapRefreshQuoteCounter(timer: swapViewModel.timer)
    }

    func getValueCell(
        for title: String,
        with value: String,
        bracketValue: String? = nil,
        showIcon: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            Text(NSLocalizedString(title, comment: ""))
                .foregroundColor(.extraLightGray)
            
            Spacer()
            
            if showIcon {
                Image(value)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            
            Text(value)
                .foregroundColor(.neutral0)
            
            if let bracketValue {
                Group {
                    Text("(") +
                    Text(bracketValue) +
                    Text(")")
                }
                .foregroundColor(.extraLightGray)
            }
            
        }
        .font(.body14BrockmannMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }



    private func getDetailsCell(for title: String, with value: String) -> some View {
        HStack {
            Text(
                NSLocalizedString(title, comment: "")
                    .replacingOccurrences(of: "Fiat", with: SettingsCurrency.current.rawValue)
            )
            Spacer()
            Text(value)
        }
        .font(.body16MenloBold)
        .foregroundColor(.neutral100)
    }
    
    private func getSwapAssetCell(
        for amount: String,
        with ticker: String,
        on chain: Chain? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                Text(amount)
                    .foregroundColor(.neutral0) +
                Text(" ") +
                Text(ticker)
                    .foregroundColor(.extraLightGray)
            }
            .font(.body18BrockmannMedium)
            
            if let chain {
                HStack(spacing: 2) {
                    Text(NSLocalizedString("on", comment: ""))
                        .foregroundColor(.extraLightGray)
                        .padding(.trailing, 4)
                    
                    Image(chain.logo)
                        .resizable()
                        .frame(width: 12, height: 12)
                    
                    Text(chain.name)
                        .foregroundColor(.neutral0)
                    
                    Spacer()
                }
                .font(.body10BrockmannMedium)
                .offset(x: 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func getCoinIcon(for coin: Coin) -> some View {
        AsyncImageView(
            logo: coin.logo,
            size: CGSize(width: 28, height: 28),
            ticker: coin.ticker,
            tokenChainLogo: nil
        )
        .overlay(
            Circle()
                .stroke(Color.blue400, lineWidth: 2)
        )
    }
}

#Preview {
    SwapVerifyView(
        tx: SwapTransaction(),
        swapViewModel: SwapCryptoViewModel(),
        vault: Vault.example
    )
    .environmentObject(SettingsViewModel())
}
