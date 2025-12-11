//
//  CircleWithdrawView.swift
//  VultisigApp
//
//  Created by Antigravity on 2025-12-11.
//

import SwiftUI
import BigInt
import WalletCore
import VultisigCommonData

struct CircleWithdrawView: View {
    let vault: Vault
    @ObservedObject var model: CircleViewModel
    
    @State private var recipientAddress: String = ""
    @State private var amount: String = ""
    @State private var isLoading = false
    @State private var error: Error?
    @State private var keysignPayload: KeysignPayload?
    
    // Dummy SendTransaction to satisfy SendRouteBuilder
    @StateObject private var sendTransaction = SendTransaction()
    
    var body: some View {
        ZStack {
            Theme.colors.bgPrimary.ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text(NSLocalizedString("circleWithdrawTitle", comment: "Withdraw USDC"))
                    .font(.title2)
                    .bold()
                    .foregroundStyle(Theme.colors.textPrimary)
                    .padding(.top, 20)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("circleWithdrawToAddress", comment: "To Address"))
                        .foregroundStyle(Theme.colors.textPrimary)
                    TextField(NSLocalizedString("circleWithdrawAddressPlaceholder", comment: "0x..."), text: $recipientAddress)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disableAutocorrection(true)
                        .textContentType(.oneTimeCode)
                }
                .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("circleWithdrawAmount", comment: "Amount (USDC)"))
                        .foregroundStyle(Theme.colors.textPrimary)
                    TextField("0.0", text: $amount)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.horizontal)
                
                if let error = error {
                    Text(error.localizedDescription)
                        .foregroundStyle(Theme.colors.alertError)
                        .font(.caption)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                } else {
                    PrimaryButton(title: NSLocalizedString("circleWithdrawConfirm", comment: "Confirm Withdrawal")) {
                        Task { await handleWithdraw() }
                    }
                    .padding()
                    .disabled(recipientAddress.isEmpty || amount.isEmpty)
                }
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
    
    private func handleWithdraw() async {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            let amountVal: BigInt = BigInt(amount) ?? BigInt(0)
            let logic: CircleViewLogic = model.logic
            let v: Vault = vault
            let r: String = recipientAddress
            
            let payload: KeysignPayload = try await logic.getWithdrawalPayload(
                vault: v,
                recipient: r,
                amount: amountVal
            )
            
            // Determine USDC Coin for display context in SendTransaction
            let usdc = vault.coins.first(where: { $0.ticker == "USDC" && $0.chain == .ethereum })
            let eth = vault.coins.first(where: { $0.chain == .ethereum })
            
            let coinToUse: Coin
            if let usdc {
                coinToUse = usdc
            } else if let eth {
                coinToUse = eth
            } else {
                let meta = CoinMeta(
                    chain: .ethereum,
                    ticker: "ETH",
                    logo: "ethereum",
                    decimals: 18,
                    priceProviderId: "ethereum",
                    contractAddress: "",
                    isNativeToken: true
                )
                coinToUse = Coin(asset: meta, address: "", hexPublicKey: vault.pubKeyECDSA)
            }
            
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
