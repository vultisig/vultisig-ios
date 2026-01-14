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
    @State private var signButtonDisabled = false
    
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
            // Clear password if navigating back (not forward to keysign)
            if swapViewModel.keysignPayload == nil {
                tx.fastVaultPassword = .empty
            }
        }
        .onLoad {
            referredViewModel.setData()
            verifyViewModel.onLoad()
            Task {
                await verifyViewModel.scan(transaction: tx, vault: vault)
            }
        }
        .bottomSheet(isPresented: $verifyViewModel.showSecurityScannerSheet) {
            SecurityScannerBottomSheet(securityScannerModel: verifyViewModel.securityScannerState.result) {
                verifyViewModel.showSecurityScannerSheet = false
                signAndMoveToNextView()
            } onDismissRequest: {
                verifyViewModel.showSecurityScannerSheet = false
            }
        }
    }
    
    var view: some View {
        container
    }
    
    var content: some View {
        VStack(spacing: 16) {
            fields
            signButton
                .padding(.horizontal, 16)
                .disabled(!verifyViewModel.isValidForm(shouldApprove: tx.isApproveRequired) || swapViewModel.isLoadingFees || signButtonDisabled)
        }
    }
    
    var summary: some View {
        VStack(spacing: 16) {
            SecurityScannerHeaderView(state: verifyViewModel.securityScannerState)
            
            VStack(spacing: 16) {
                summaryTitle
                summaryFromTo
                
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
                    getNetworkFeeCell(
                        cryptoAmount: swapViewModel.swapGasString(tx: tx),
                        fiatAmount: swapViewModel.approveFeeString(tx: tx)
                    )
                    .blur(radius: swapViewModel.isLoadingFees ? 1 : 0)
                }
                
                if swapViewModel.showFees(tx: tx) {
                    separator
                    getValueCell(
                        for: "swapFee",
                        with: swapViewModel.swapFeeString(tx: tx),
                        bracketValue:nil
                    )
                    .blur(radius: swapViewModel.isLoadingFees ? 1 : 0)
                }
                
                if swapViewModel.showTotalFees(tx: tx) {
                    separator
                    getValueCell(
                        for: "maxTotalFee",
                        with: swapViewModel.totalFeeString(tx: tx)
                    )
                    .blur(radius: swapViewModel.isLoadingFees ? 1 : 0)
                }
                
                separator
                getValueCell(
                    for: "vault",
                    with: vault.name
                )
            }
            .padding(16)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(10)
        }
    }
    
    var summaryFromToIcons: some View {
        HStack(spacing: 10) {
            ZStack {
                verticalSeparator
                chevronIcon
            }
            
            Text("to".localized)
                .font(Theme.fonts.caption10)
                .foregroundStyle(Theme.colors.textTertiary)
            separator
        }
    }
    
    var verticalSeparator: some View {
        Rectangle()
            .frame(width: 1)
            .frame(idealHeight: 80, maxHeight: 100)
            .foregroundColor(Theme.colors.bgSurface2)
    }
    
    var summaryFromTo: some View {
        VStack(spacing: 0) {
            getSwapAssetCell(
                for: tx.fromAmountDecimal.formatForDisplay(),
                with: tx.fromCoin.ticker,
                fiatValue: swapViewModel.fromFiatAmount(tx: tx).formatToFiat(includeCurrencySymbol: true),
                on: tx.fromCoin.chain,
                coin: tx.fromCoin,
                isTo: false
            )
            
            summaryFromToIcons
            
            getSwapAssetCell(
                for: tx.toAmountDecimal.formatForDisplay(),
                with: tx.toCoin.ticker,
                fiatValue: swapViewModel.toFiatAmount(tx: tx).formatToFiat(includeCurrencySymbol: true),
                on: tx.toCoin.chain,
                coin: tx.toCoin,
                isTo: true
            )
        }
    }
    
    var chevronIcon: some View {
        Image(systemName: "arrow.down")
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.primaryAccent4)
            .padding(6)
            .background(Theme.colors.bgSurface2)
            .cornerRadius(32)
            .bold()
    }
    
    var summaryTitle: some View {
        Text(NSLocalizedString("youreSwapping", comment: ""))
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textSecondary)
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
    
    @ViewBuilder
    var signButton: some View {
        if tx.isFastVault {
            Text(NSLocalizedString("holdForPairedSign", comment: ""))
                .foregroundColor(Theme.colors.textTertiary)
                .font(Theme.fonts.bodySMedium)
            
            LongPressPrimaryButton(title: NSLocalizedString("signTransaction", comment: "")) {
                fastPasswordPresented = true
            } longPressAction: {
                // Clear password for paired sign (long press)
                tx.fastVaultPassword = .empty
                onSignPress()
            }
            .disabled(signButtonDisabled)
            .crossPlatformSheet(isPresented: $fastPasswordPresented) {
                FastVaultEnterPasswordView(
                    password: $tx.fastVaultPassword,
                    vault: vault,
                    onSubmit: { onSignPress() }
                )
            }
        } else {
            PrimaryButton(title: NSLocalizedString("signTransaction", comment: "")) {
                onSignPress()
            }.disabled(signButtonDisabled)
        }
    }
    
    private func onSignPress() {
        let canSign = verifyViewModel.validateSecurityScanner()
        if canSign {
            signAndMoveToNextView()
        }
    }
    
    func signAndMoveToNextView() {
        signButtonDisabled = true
        Task {
            if await swapViewModel.buildSwapKeysignPayload(tx: tx, vault: vault) {
                swapViewModel.moveToNextView()
            }
            await MainActor.run { signButtonDisabled = false }
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
                .foregroundColor(Theme.colors.textTertiary)
            
            Spacer()
            
            if showIcon {
                Image(value)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            
            Text(value)
                .foregroundColor(Theme.colors.textPrimary)
            
            if let bracketValue {
                Group {
                    Text("(") +
                    Text(bracketValue) +
                    Text(")")
                }
                .foregroundColor(Theme.colors.textTertiary)
            }
            
        }
        .font(Theme.fonts.bodySMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func getNetworkFeeCell(
        cryptoAmount: String,
        fiatAmount: String
    ) -> some View {
        HStack(spacing: 4) {
            Text(NSLocalizedString("networkFee", comment: ""))
                .foregroundColor(Theme.colors.textTertiary)
                .font(Theme.fonts.bodySMedium)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(cryptoAmount)
                    .foregroundColor(Theme.colors.textPrimary)
                    .font(Theme.fonts.bodySMedium)
                
                Text(fiatAmount)
                    .foregroundColor(Theme.colors.textTertiary)
                    .font(Theme.fonts.caption12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func getSwapAssetCell(
        for amount: String,
        with ticker: String,
        fiatValue: String,
        on chain: Chain? = nil,
        coin: Coin,
        isTo: Bool
    ) -> some View {
        HStack(spacing: 8) {
            getCoinIcon(for: coin)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("minPayout".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundColor(Theme.colors.textTertiary)
                    .opacity(isTo ? 1 : 0)
                Group {
                    Text(amount)
                        .foregroundColor(Theme.colors.textPrimary) +
                    Text(" ") +
                    Text(ticker)
                        .foregroundColor(Theme.colors.textTertiary)
                }
                .font(Theme.fonts.bodyLMedium)
                
                HStack(spacing: 0) {
                    Text(fiatValue)
                        .font(Theme.fonts.caption12)
                        .foregroundColor(Theme.colors.textTertiary)
                    Spacer()
                    if let chain {
                        HStack(spacing: 2) {
                            Spacer()
                            
                            Text(NSLocalizedString("on", comment: ""))
                                .foregroundColor(Theme.colors.textTertiary)
                                .padding(.trailing, 4)
                            
                            Image(chain.logo)
                                .resizable()
                                .frame(width: 12, height: 12)
                            
                            Text(chain.name)
                                .foregroundColor(Theme.colors.textPrimary)
                        }
                        .font(Theme.fonts.caption10)
                        .offset(x: 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                .stroke(Theme.colors.bgSurface2, lineWidth: 2)
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
