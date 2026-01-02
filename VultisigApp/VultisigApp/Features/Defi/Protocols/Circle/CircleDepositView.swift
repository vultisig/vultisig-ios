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
                    
                    Text("\(Int(percentage))%")
                        .font(CircleConstants.Fonts.subtitle)
                        .foregroundStyle(Theme.colors.textSecondary)
                }
                
                Spacer()
                
                VStack(spacing: CircleConstants.Design.verticalSpacing) {
                    Slider(value: Binding(
                        get: { percentage },
                        set: { newValue in
                            percentage = newValue
                            updateAmount(from: newValue)
                        }
                    ), in: 0...100)
                    .accentColor(Theme.colors.primaryAccent1)
                    
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
        TextField("0", text: $amount)
            .font(.system(size: 40, weight: .bold))
            .foregroundStyle(Theme.colors.textPrimary)
            .multilineTextAlignment(.center)
            #if os(macOS)
            .textFieldStyle(.plain)
            #endif
            .onChange(of: amount) { newValue in
                updatePercentage(from: newValue)
            }
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
    
    func updatePercentage(from amountStr: String) {
        guard let coin = usdcCoin, let amountDec = Decimal(string: amountStr), coin.balanceDecimal > 0 else {
            return
        }
        let percent = (amountDec / coin.balanceDecimal) * 100
        if abs(self.percentage - Double(truncating: percent as NSNumber)) > 0.1 {
            self.percentage = Double(truncating: percent as NSNumber)
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
