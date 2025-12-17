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
    
    @State var amount: String = ""
    @State var percentage: Double = 0.0
    @State var isLoading = false
    @State var error: Error?
    @State var keysignPayload: KeysignPayload?
    @State var isFastVault = false
    @State var fastPasswordPresented = false
    @State var fastVaultPassword: String = ""
    
    @StateObject var sendTransaction = SendTransaction()
    
    var body: some View {
        NavigationStack {
            main
        }
    }

    var content: some View {
        ZStack {
            VStack(spacing: 0) {
                headerView
                scrollableContent
                footerView
            }
            
            if isLoading {
                Color.black.opacity(0.5).ignoresSafeArea()
                ProgressView()
            }
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
            
            Text(NSLocalizedString("circleWithdrawTitle", comment: "Withdraw from Circle"))
                .font(.headline)
                .bold()
                .foregroundStyle(Theme.colors.textPrimary)
            
            Spacer()
            
            Color.clear.frame(width: 40, height: 40)
        }
        .padding()
    }
    
    var footerView: some View {
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
    
    var scrollableContent: some View {
        VStack(spacing: 24) {
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
    
    var amountTextField: some View {
        TextField("0", text: $amount)
            .font(.system(size: 40, weight: .bold))
            .foregroundStyle(Theme.colors.textPrimary)
            .multilineTextAlignment(.center)
            .onChange(of: amount) { newValue in
                updatePercentage(from: newValue)
            }
    }

    @ViewBuilder
    var withdrawButton: some View {
        if isFastVault {
            VStack {
                Text(NSLocalizedString("holdForPairedSign", comment: ""))
                    .foregroundColor(Theme.colors.textExtraLight)
                    .font(Theme.fonts.bodySMedium)
                
                LongPressPrimaryButton(title: NSLocalizedString("circleWithdrawConfirm", comment: "Continue")) {
                    fastPasswordPresented = true
                } longPressAction: {
                    fastVaultPassword = ""
                    Task { await handleWithdraw() }
                }
            }
            .disabled(isButtonDisabled)
        } else {
            PrimaryButton(title: NSLocalizedString("circleWithdrawConfirm", comment: "Continue")) {
                Task { await handleWithdraw() }
            }
            .disabled(isButtonDisabled)
        }
    }
    
    var vaultEthBalance: Decimal {
        let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
        let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
        return vault.coins.first(where: { $0.chain == chain && $0.isNativeToken })?.balanceDecimal ?? 0
    }
    
    var isButtonDisabled: Bool {
        amount.isEmpty || (Decimal(string: amount) ?? 0) <= 0 || (Decimal(string: amount) ?? 0) > model.balance || vaultEthBalance <= 0 || isLoading
    }

    func loadFastVaultStatus() async {
        let isExist = await FastVaultService.shared.exist(pubKeyECDSA: vault.pubKeyECDSA)
        let isLocalBackup = vault.localPartyID.lowercased().contains("server-")
        
        await MainActor.run {
            isFastVault = isExist && !isLocalBackup
        }
    }
    
    func updatePercentage(from amountStr: String) {
        let balance = model.balance
        guard let amountDec = Decimal(string: amountStr), balance > 0 else {
            return
        }
        let percent = (amountDec / balance) * 100
        if abs(self.percentage - Double(truncating: percent as NSNumber)) > 0.1 {
            self.percentage = Double(truncating: percent as NSNumber)
        }
    }
    
    func updateAmount(from percent: Double) {
        let balance = model.balance
        guard balance > 0 else { return }
        let amountDec = balance * Decimal(percent) / 100
        let newAmount = amountDec.truncated(toPlaces: 6).description
        if self.amount != newAmount {
            self.amount = newAmount
        }
    }
    
    func handleWithdraw() async {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            guard let amountDecimal = Decimal(string: amount) else { return }
            
            let decimals = 6
            let amountUnits = (amountDecimal * pow(10, decimals)).description
            let cleanAmountUnits = amountUnits.components(separatedBy: ".").first ?? amountUnits
            let amountVal = BigInt(cleanAmountUnits) ?? BigInt(0)
            
            let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
            let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
            guard let recipientCoin = vault.coins.first(where: { $0.chain == chain }) else {
                throw NSError(domain: "CircleWithdraw", code: 404, userInfo: [NSLocalizedDescriptionKey: "ETH address not found"])
            }
            
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
                if case .walletNotDeployed = err {
                     let _ = try? await CircleApiService.shared.createWallet(
                        ethAddress: recipientCoin.address,
                        force: true
                     )
                     payload = try await attemptPayload()
                } else {
                    throw err
                }
            } catch {
                throw error
            }
            
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
