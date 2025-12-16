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
    @State private var isFastVault = false
    @State private var fastPasswordPresented = false
    @State private var fastVaultPassword: String = ""
    
    // SendTransaction for routing
    @StateObject private var sendTransaction = SendTransaction()
    
    var body: some View {
        NavigationStack {
            #if os(iOS)
            ZStack {
                Theme.colors.bgPrimary.ignoresSafeArea()
                content
            }
            .onAppear {
                Task {
                    let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
                    let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
                    let vaultCoin = vault.coins.first(where: { $0.chain == chain && $0.isNativeToken })
                    
                    await loadFastVaultStatus()
                }
            }
            .navigationDestination(item: $keysignPayload) { payload in
                SendRouteBuilder().buildPairScreen(
                    vault: vault,
                    tx: sendTransaction,
                    keysignPayload: payload,
                    fastVaultPassword: fastVaultPassword.nilIfEmpty
                )
            }
            .crossPlatformSheet(isPresented: $fastPasswordPresented) {
                FastVaultEnterPasswordView(
                    password: $fastVaultPassword,
                    vault: vault,
                    onSubmit: { Task { await handleWithdraw() } }
                )
            }
            #else
            content
                .background(Theme.colors.bgPrimary)
                .onAppear {
                    Task {
                        let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
                        let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
                        let vaultCoin = vault.coins.first(where: { $0.chain == chain && $0.isNativeToken })
                        
                        await loadFastVaultStatus()
                    }
                }
                .navigationDestination(item: $keysignPayload) { payload in
                    SendRouteBuilder().buildPairScreen(
                        vault: vault,
                        tx: sendTransaction,
                        keysignPayload: payload,
                        fastVaultPassword: fastVaultPassword.nilIfEmpty
                    )
                }
                .crossPlatformSheet(isPresented: $fastPasswordPresented) {
                    FastVaultEnterPasswordView(
                        password: $fastVaultPassword,
                        vault: vault,
                        onSubmit: { Task { await handleWithdraw() } }
                    )
                }
            #endif
        }
    }

    var content: some View {
        ZStack {
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
            
            #if os(iOS)
            ScrollView {
                scrollableContent
            }
            #else
            scrollableContent
            #endif
            
            // Footer Button and Warnings
            VStack(spacing: 12) {
                if let error = error {
                    Text(error.localizedDescription)
                        .foregroundStyle(Theme.colors.alertError)
                        .font(.caption)
                }
                
                if vaultEthBalance <= 0 {
                    Text(NSLocalizedString("circleDashboardETHRequired", comment: "ETH is required..."))
                        .font(.caption)
                        .foregroundStyle(Theme.colors.alertWarning)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                withdrawButton
            }
            .padding()
            .background(Theme.colors.bgPrimary)
        }
        
        if isLoading {
            Color.black.opacity(0.5).ignoresSafeArea()
            ProgressView()
        }
        }
    }
    
    var scrollableContent: some View {
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
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
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

    
    @ViewBuilder
    private var withdrawButton: some View {
        if isFastVault {
            // Fast Vault: Show long press button with password option
            VStack {
                Text(NSLocalizedString("holdForPairedSign", comment: ""))
                    .foregroundColor(Theme.colors.textExtraLight)
                    .font(Theme.fonts.bodySMedium)
                
                LongPressPrimaryButton(title: NSLocalizedString("circleWithdrawConfirm", comment: "Continue")) {
                    // Short press: Show password entry
                    fastPasswordPresented = true
                } longPressAction: {
                    // Long press: Paired sign (no password)
                    fastVaultPassword = ""
                    Task { await handleWithdraw() }
                }
            }
            .disabled(isButtonDisabled)
        } else {
            // Normal Vault: Simple button
            PrimaryButton(title: NSLocalizedString("circleWithdrawConfirm", comment: "Continue")) {
                Task { await handleWithdraw() }
            }
            .disabled(isButtonDisabled)
        }
    }
    
    private var vaultEthBalance: Decimal {
        let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
        let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
        return vault.coins.first(where: { $0.chain == chain && $0.isNativeToken })?.balanceDecimal ?? 0
    }
    
    private var isButtonDisabled: Bool {
        amount.isEmpty || (Decimal(string: amount) ?? 0) <= 0 || (Decimal(string: amount) ?? 0) > model.balance || vaultEthBalance <= 0 || isLoading
    }

    
    private func loadFastVaultStatus() async {
        let isExist = await FastVaultService.shared.exist(pubKeyECDSA: vault.pubKeyECDSA)
        let isLocalBackup = vault.localPartyID.lowercased().contains("server-")
        
        await MainActor.run {
            isFastVault = isExist && !isLocalBackup
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
            
            // Recipient is Vault Address (ETH chain)
            let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
            let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
            guard let recipientCoin = vault.coins.first(where: { $0.chain == chain }) else {
                throw NSError(domain: "CircleWithdraw", code: 404, userInfo: [NSLocalizedDescriptionKey: "ETH address not found"])
            }
            
            // Define cleanup/retry closure to avoid repetition
            func attemptPayload() async throws -> KeysignPayload {
                return try await model.logic.getWithdrawalPayload(
                    vault: vault,
                    recipient: recipientCoin.address,
                    amount: amountVal
                )
            }
            
            let payload: KeysignPayload
            do {
                payload = try await attemptPayload()
            } catch let err as CircleServiceError {
                // Catch undeployed error specifically
                if case .keysignError(let msg) = err, msg.contains("not deployed") {
                     print("CircleWithdrawView: Wallet undeployed. Attempting Force Create logic.")
                     // Attempt force create using vault's ETH address
                     let _ = try? await CircleApiService.shared.createWallet(
                        ethAddress: recipientCoin.address,
                        force: true
                     )
                     // Retry payload generation once
                     payload = try await attemptPayload()
                } else {
                    throw err
                }
            } catch {
                throw error
            }
            
            // Setup Transaction for Routing
            let coinToUse = recipientCoin
            
            await MainActor.run {
                self.sendTransaction.reset(coin: coinToUse)
                self.sendTransaction.isFastVault = isFastVault
                self.sendTransaction.fastVaultPassword = fastVaultPassword
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
