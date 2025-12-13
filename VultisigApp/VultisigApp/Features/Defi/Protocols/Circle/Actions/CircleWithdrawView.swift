//
//  CircleWithdrawView.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-13.
//

import SwiftUI
import BigInt
import WalletCore
import VultisigCommonData

struct CircleWithdrawView: View {
    let vault: Vault
    @ObservedObject var model: CircleViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var amount: String = ""
    @State private var percentage: Double = 0.0
    @State private var isLoading = false
    @State private var error: Error?
    @State private var keysignPayload: KeysignPayload?
    
    // Dummy SendTransaction to satisfy SendRouteBuilder
    @StateObject private var sendTransaction = SendTransaction()
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.colors.bgPrimary.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Custom Header
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
                        
                        Text(NSLocalizedString("circleWithdrawTitle", comment: "Withdraw from Circle"))
                            .font(.headline)
                            .bold()
                            .foregroundStyle(Theme.colors.textPrimary)
                        
                        Spacer()
                        
                        // Invisible balancer
                        Color.clear.frame(width: 40, height: 40)
                    }
                    .padding()
                    
                    ScrollView {
                        VStack(spacing: 24) {
                            
                            // Amount Card
                            VStack(spacing: 24) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(NSLocalizedString("circleWithdrawAmount", comment: "Amount"))
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.colors.textLight)
                                    
                                    Divider()
                                        .background(Theme.colors.textExtraLight.opacity(0.2))
                                }
                                
                                VStack(spacing: 8) {
                                    HStack(spacing: 4) {
                                        TextField("0", text: $amount)
                                            .font(.system(size: 40, weight: .bold))
                                            .foregroundStyle(Theme.colors.textPrimary)
                                            .multilineTextAlignment(.center)
                                            .keyboardType(.decimalPad)
                                            .onChange(of: amount) { newValue in
                                                updatePercentage(from: newValue)
                                            }
                                        
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
                                    
                                    Text("\(model.balance.formatted()) USDC")
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
                    
                    // Footer Button and Warnings
                    VStack(spacing: 12) {
                        if let error = error {
                            Text(error.localizedDescription)
                                .foregroundStyle(Theme.colors.alertError)
                                .font(.caption)
                        }
                        
                         if model.ethBalance <= 0 {
                            Text(NSLocalizedString("circleDashboardETHRequired", comment: "ETH is required..."))
                                .font(.caption)
                                .foregroundStyle(Theme.colors.alertWarning)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        PrimaryButton(title: NSLocalizedString("circleWithdrawConfirm", comment: "Continue")) { // "Continue" per spec, using existing key or localized literal
                            Task { await handleWithdraw() }
                        }
                        .disabled(amount.isEmpty || (Decimal(string: amount) ?? 0) <= 0 || (Decimal(string: amount) ?? 0) > model.balance || model.ethBalance <= 0 || isLoading)
                    }
                    .padding()
                    .background(Theme.colors.bgPrimary)
                }
                
                if isLoading {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    ProgressView()
                }
            }
             .navigationDestination(item: $keysignPayload) { payload in
                SendRouteBuilder().buildPairScreen(
                    vault: vault,
                    tx: sendTransaction,
                    keysignPayload: payload,
                    fastVaultPassword: nil
                )
            }
        }
    }
    
    private func updatePercentage(from amountStr: String) {
        let balance = model.balance
        guard let amountDec = Decimal(string: amountStr), balance > 0 else {
            return
        }
        let percent = (amountDec / balance) * 100
        if abs(self.percentage - Double(truncating: percent as NSNumber)) > 0.1 {
            self.percentage = Double(truncating: percent as NSNumber)
        }
    }
    
    private func updateAmount(from percent: Double) {
        let balance = model.balance
        guard balance > 0 else { return }
        let amountDec = balance * Decimal(percent) / 100
        let newAmount = amountDec.truncated(toPlaces: 6).description
        if self.amount != newAmount {
            self.amount = newAmount
        }
    }
    
    private func handleWithdraw() async {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            guard let amountDecimal = Decimal(string: amount) else { return }
            
            // Convert to Units (USDC = 6 decimals)
            let decimals = 6
            let amountUnits = (amountDecimal * pow(10, decimals)).description
            let cleanAmountUnits = amountUnits.components(separatedBy: ".").first ?? amountUnits
            let amountVal = BigInt(cleanAmountUnits) ?? BigInt(0)
            
            // Recipient is Vault Address
            // Which one? The one matching the chain.
            // Circle supports ETH. So ETH address.
            guard let recipientCoin = vault.coins.first(where: { $0.chain == .ethereum }) else {
                 throw NSError(domain: "CircleWithdraw", code: 404, userInfo: [NSLocalizedDescriptionKey: "ETH address not found"])
            }
            
            let payload = try await model.logic.getWithdrawalPayload(
                vault: vault,
                recipient: recipientCoin.address,
                amount: amountVal
            )
            
            // Setup Dummy Transaction for Routing
            // We need a coin for the "SendTransaction" context to render details correctly in Keysign
            let coinToUse = recipientCoin // Use ETH coin as context or USDC if present
            
            await MainActor.run {
                self.sendTransaction.reset(coin: coinToUse)
                self.keysignPayload = payload
                isLoading = false
            }
            
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }
}
