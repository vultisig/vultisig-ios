//
//  CircleDepositView.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-13.
//

import SwiftUI
import BigInt
import WalletCore
import VultisigCommonData

struct CircleDepositView: View {
    let vault: Vault
    @Environment(\.dismiss) var dismiss
    @Environment(\.router) var router
    
    @StateObject var tx = SendTransaction()
    @StateObject var sendCryptoViewModel = SendCryptoViewModel()
    @State var amount: String = ""
    @State var percentage: Double = 0.0
    @State var usdcCoin: Coin?
    @State var error: Error?
    @State var isLoading = false
    
    var body: some View {
        main
    }

    var content: some View {
        VStack(spacing: 0) {
            headerView
            scrollableContent
            footerView
        }
    }
    
    var headerView: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundColor(Theme.colors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            
            Spacer()
            
            Text(NSLocalizedString("circleDepositTitle", comment: "Deposit to Circle Account"))
                .font(Theme.fonts.bodyLMedium)
                .foregroundStyle(Theme.colors.textPrimary)
            
            Spacer()
            
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(CircleConstants.Design.horizontalPadding)
    }
    
    var footerView: some View {
        VStack {
            if let error = error {
                Text(error.localizedDescription)
                    .foregroundStyle(Theme.colors.alertError)
                    .font(.caption)
                    .padding(.bottom, 8)
            }
            
            if isLoading {
                ProgressView()
                    .padding()
            } else {
                PrimaryButton(title: NSLocalizedString("circleDepositContinue", comment: "Continue")) {
                    Task { await handleContinue() }
                }
                .disabled(amount.isEmpty || (Decimal(string: amount) ?? 0) <= 0 || (Decimal(string: amount) ?? 0) > (usdcCoin?.balanceDecimal ?? 0))
            }
        }
        .padding(CircleConstants.Design.horizontalPadding)
        .background(Theme.colors.bgPrimary)
    }
    
    var scrollableContent: some View {
        VStack(spacing: CircleConstants.Design.verticalSpacing) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("circleDepositAmount", comment: "Amount"))
                        .font(CircleConstants.Fonts.subtitle)
                        .foregroundStyle(Theme.colors.textSecondary)
                    
                    Divider()
                        .background(Theme.colors.textTertiary.opacity(0.2))
                }
                
                Spacer()
                
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        amountTextField
                        
                        Text("USDC")
                            .font(Theme.fonts.bodyLMedium)
                            .foregroundStyle(Theme.colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Text("\(Int(min(percentage, 100)))%")
                        .font(CircleConstants.Fonts.subtitle)
                        .foregroundStyle(Theme.colors.textSecondary)
                }
                
                Spacer()
                
                VStack(spacing: CircleConstants.Design.verticalSpacing) {
                    HStack(spacing: 12) {
                        Text("0%")
                            .font(CircleConstants.Fonts.subtitle)
                            .foregroundStyle(Theme.colors.textSecondary)
                        
                        ZStack(alignment: .center) {
                            // Tick marks at 25%, 50%, 75%
                            GeometryReader { geometry in
                                ZStack {
                                    Circle()
                                        .fill(Theme.colors.textTertiary)
                                        .frame(width: 6, height: 6)
                                        .position(x: geometry.size.width * 0.25, y: geometry.size.height / 2)
                                    
                                    Circle()
                                        .fill(Theme.colors.textTertiary)
                                        .frame(width: 6, height: 6)
                                        .position(x: geometry.size.width * 0.5, y: geometry.size.height / 2)
                                    
                                    Circle()
                                        .fill(Theme.colors.textTertiary)
                                        .frame(width: 6, height: 6)
                                        .position(x: geometry.size.width * 0.75, y: geometry.size.height / 2)
                                }
                            }
                            .frame(height: 20)
                            
                            Slider(value: Binding(
                                get: { percentage },
                                set: { newValue in
                                    percentage = newValue
                                    updateAmount(from: newValue)
                                }
                            ), in: 0...100)
                            .accentColor(Theme.colors.primaryAccent1)
                        }
                        
                        Text("100%")
                            .font(CircleConstants.Fonts.subtitle)
                            .foregroundStyle(Theme.colors.textSecondary)
                    }
                    
                    percentageCheckpoints
                    
                    HStack {
                        Text(NSLocalizedString("circleDepositBalanceAvailable", comment: "Balance available:"))
                            .font(CircleConstants.Fonts.subtitle)
                            .foregroundStyle(Theme.colors.textSecondary)
                        
                        Spacer()
                        
                        Text("\(usdcCoin?.balanceString ?? "0") USDC")
                            .font(CircleConstants.Fonts.subtitle)
                            .bold()
                            .foregroundStyle(Theme.colors.textPrimary)
                    }
                }
            }
            .padding(CircleConstants.Design.cardPadding)

            .padding(.horizontal, CircleConstants.Design.horizontalPadding)
        }
        .padding(.top, CircleConstants.Design.verticalSpacing)
        .frame(maxHeight: .infinity)
    }
    


    var amountTextField: some View {
        SendCryptoAmountTextField(
            amount: $amount,
            onChange: { await updatePercentage(from: $0) }
        )
    }
    
    var percentageCheckpoints: some View {
        HStack(spacing: 8) {
            ForEach([25, 50, 75, 100], id: \.self) { value in
                PrimaryButton(
                    title: "\(value)%",
                    type: isPercentageSelected(value) ? .primary : .secondary,
                    size: .mini
                ) {
                    percentage = Double(value)
                    updateAmount(from: Double(value))
                }
            }
        }
    }
    
    func isPercentageSelected(_ value: Int) -> Bool {
        abs(percentage - Double(value)) < 1.0
    }
    
    func loadData() async {
        let (chain, _) = CircleViewLogic.getChainDetails(vault: vault)
        
        if let coin = vault.coins.first(where: { $0.chain == chain && $0.ticker == "USDC" }) {
            await BalanceService.shared.updateBalance(for: coin)
            
            await MainActor.run {
                self.usdcCoin = coin
                tx.reset(coin: coin)
            }
            await sendCryptoViewModel.loadFastVault(tx: tx, vault: vault)
        }
    }
    
    func updatePercentage(from amountStr: String) async {
        guard let coin = usdcCoin, let amountDec = Decimal(string: amountStr), coin.balanceDecimal > 0 else {
            return
        }
        let percent = (amountDec / coin.balanceDecimal) * 100
        let cappedPercent = min(Double(truncating: percent as NSNumber), 100.0)
        
        if abs(self.percentage - cappedPercent) > 0.1 {
            await MainActor.run {
                self.percentage = cappedPercent
            }
        }
    }
    
    func updateAmount(from percent: Double) {
        guard let coin = usdcCoin else { return }
        let amountDec = coin.balanceDecimal * Decimal(percent) / 100
        let newAmount = amountDec.truncated(toPlaces: 6).description
        if self.amount != newAmount {
            self.amount = newAmount
        }
    }
    
    func handleContinue() async {
        guard let coin = usdcCoin, let amountDec = Decimal(string: amount), let toAddress = vault.circleWalletAddress else {
            return
        }
        
        await MainActor.run { isLoading = true }
        
        tx.coin = coin
        tx.fromAddress = coin.address
        tx.toAddress = toAddress
        tx.amount = amountDec.description
        
        await sendCryptoViewModel.loadFastVault(tx: tx, vault: vault)
        
        await MainActor.run {
            isLoading = false
            router.navigate(to: SendRoute.verify(tx: tx, vault: vault))
        }
    }
}
