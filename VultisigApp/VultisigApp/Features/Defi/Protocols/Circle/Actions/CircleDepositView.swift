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
    
    @StateObject var tx = SendTransaction()
    @StateObject var sendCryptoViewModel = SendCryptoViewModel()
    @State var amount: String = ""
    @State var percentage: Double = 0.0
    @State var usdcCoin: Coin?
    @State var navigateToVerify = false
    @State var error: Error?
    @State var isLoading = false
    
    var body: some View {
        main
    }

    var content: some View {
        VStack(spacing: 0) {
            headerView
            scrollView
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
                .font(.headline)
                .bold()
                .foregroundStyle(Theme.colors.textPrimary)
            
            Spacer()
            
            Color.clear.frame(width: 40, height: 40)
        }
        .padding()
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
        .padding()
        .background(Theme.colors.bgPrimary)
    }
    
    var scrollableContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("circleDepositAmount", comment: "Amount"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.colors.textLight)
                    
                    Divider()
                        .background(Theme.colors.textExtraLight.opacity(0.2))
                }
                
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        amountTextField
                        
                        Text("USDC")
                            .font(.title2)
                            .bold()
                            .foregroundStyle(Theme.colors.textLight)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Text("\(Int(percentage))%")
                        .font(.caption)
                        .foregroundStyle(Theme.colors.textLight)
                }
                .padding(.vertical, 20)
                
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
                        .font(.caption)
                        .foregroundStyle(Theme.colors.textLight)
                    
                    Spacer()
                    
                    Text("\(usdcCoin?.balanceString ?? "0") USDC")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(Theme.colors.textPrimary)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.colors.bgSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Theme.colors.borderLight, lineWidth: 1)
                    )
            )
            .padding(.horizontal)
        }
        .padding(.top, 20)
    }

    var amountTextField: some View {
        TextField("0", text: $amount)
            .font(.system(size: 40, weight: .bold))
            .foregroundStyle(Theme.colors.textPrimary)
            .multilineTextAlignment(.center)
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
            navigateToVerify = true
        }
    }
}
