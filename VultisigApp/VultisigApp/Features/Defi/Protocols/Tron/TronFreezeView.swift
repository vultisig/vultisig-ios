//
//  TronFreezeView.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI
import BigInt

struct TronFreezeView: View {
    let vault: Vault
    @Environment(\.dismiss) var dismiss
    @Environment(\.router) var router
    
    @StateObject var tx = SendTransaction()
    @StateObject var sendCryptoViewModel = SendCryptoViewModel()
    @State var amount: String = ""
    @State var percentage: Double = 0.0
    @State var trxCoin: Coin?
    @State var error: Error?
    @State var isLoading = false
    @State var selectedResourceType: TronResourceType = .bandwidth
    @State var isFastVault = false
    @State var fastPasswordPresented = false
    @State var fastVaultPassword: String = ""
    
    var body: some View {
        main
    }

    var content: some View {
        ZStack {
            VStack(spacing: 0) {
                headerView
                scrollableContent
                footerView
            }
            
            if isLoading {
                Theme.colors.bgPrimary.opacity(0.8).ignoresSafeArea()
                ProgressView()
            }
        }
        .task {
            await loadData()
            await loadFastVaultStatus()
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
                    .background(Circle().fill(Theme.colors.bgSurface1))
            }
            
            Spacer()
            
            Text(NSLocalizedString("tronFreezeTitle", comment: "Freeze TRX"))
                .font(Theme.fonts.bodyLMedium)
                .foregroundStyle(Theme.colors.textPrimary)
            
            Spacer()
            
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(TronConstants.Design.horizontalPadding)
    }
    
    var footerView: some View {
        VStack(spacing: 12) {
            if let error = error {
                Text(error.localizedDescription)
                    .foregroundStyle(Theme.colors.alertError)
                    .font(Theme.fonts.caption12)
            }
            
            freezeButton
        }
        .padding(TronConstants.Design.horizontalPadding)
        .background(Theme.colors.bgPrimary)
    }
    
    @ViewBuilder
    var freezeButton: some View {
        if isFastVault {
            VStack {
                Text(NSLocalizedString("holdForPairedSign", comment: ""))
                    .foregroundColor(Theme.colors.textTertiary)
                    .font(Theme.fonts.bodySMedium)
                
                LongPressPrimaryButton(title: NSLocalizedString("tronFreezeContinue", comment: "Continue")) {
                    fastPasswordPresented = true
                } longPressAction: {
                    fastVaultPassword = ""
                    Task { await handleContinue() }
                }
            }
            .disabled(isButtonDisabled)
        } else {
            PrimaryButton(title: NSLocalizedString("tronFreezeContinue", comment: "Continue")) {
                Task { await handleContinue() }
            }
            .disabled(isButtonDisabled)
        }
    }
    
    var isButtonDisabled: Bool {
        amount.isEmpty || (Decimal(string: amount) ?? 0) <= 0 || (Decimal(string: amount) ?? 0) > (trxCoin?.balanceDecimal ?? 0) || isLoading
    }
    
    var scrollableContent: some View {
        VStack(spacing: TronConstants.Design.verticalSpacing) {
            // Resource Type Picker
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("tronResourceType", comment: "Resource Type"))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)
                
                Picker("", selection: $selectedResourceType) {
                    ForEach(TronResourceType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, TronConstants.Design.horizontalPadding)
            
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("tronFreezeAmount", comment: "Amount"))
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textSecondary)
                    
                    Divider()
                        .background(Theme.colors.textTertiary.opacity(0.2))
                }
                
                Spacer()
                
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        amountTextField
                        
                        Text("TRX")
                            .font(Theme.fonts.bodyLMedium)
                            .foregroundStyle(Theme.colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Text("\(Int(min(percentage, 100)))%")
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textSecondary)
                }
                
                Spacer()
                
                VStack(spacing: TronConstants.Design.verticalSpacing) {
                    percentageCheckpoints
                    
                    HStack {
                        Text(NSLocalizedString("tronFreezeBalanceAvailable", comment: "Balance available:"))
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textSecondary)
                        
                        Spacer()
                        
                        Text("\(trxCoin?.balanceString ?? "0") TRX")
                            .font(Theme.fonts.caption12)
                            .bold()
                            .foregroundStyle(Theme.colors.textPrimary)
                    }
                }
            }
            .padding(TronConstants.Design.cardPadding)

            .padding(.horizontal, TronConstants.Design.horizontalPadding)
        }
        .padding(.top, TronConstants.Design.verticalSpacing)
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
        if let coin = vault.coins.first(where: { $0.chain == .tron && $0.isNativeToken }) {
            await BalanceService.shared.updateBalance(for: coin)
            
            await MainActor.run {
                self.trxCoin = coin
                tx.reset(coin: coin)
            }
            await sendCryptoViewModel.loadFastVault(tx: tx, vault: vault)
        }
    }
    
    func loadFastVaultStatus() async {
        let isExist = await FastVaultService.shared.exist(pubKeyECDSA: vault.pubKeyECDSA)
        let isLocalBackup = vault.localPartyID.lowercased().contains("server-")
        
        await MainActor.run {
            isFastVault = isExist && !isLocalBackup
        }
    }
    
    func updatePercentage(from amountStr: String) async {
        guard let coin = trxCoin, let amountDec = Decimal(string: amountStr), coin.balanceDecimal > 0 else {
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
        guard let coin = trxCoin else { return }
        let amountDec = coin.balanceDecimal * Decimal(percent) / 100
        let newAmount = amountDec.truncated(toPlaces: 6).description
        if self.amount != newAmount {
            self.amount = newAmount
        }
    }
    
    func handleContinue() async {
        guard let coin = trxCoin, let amountDec = Decimal(string: amount) else {
            return
        }
        
        await MainActor.run { isLoading = true }
        
        // Configure SendTransaction for the freeze operation
        // The memo encodes the freeze operation type for TronHelper
        let memo = "FREEZE:\(selectedResourceType.tronResourceString)"
        
        tx.coin = coin
        tx.fromAddress = coin.address
        tx.toAddress = coin.address  // Freeze goes to self
        tx.amount = amountDec.description
        tx.memo = memo
        tx.isFastVault = isFastVault
        tx.fastVaultPassword = fastVaultPassword
        
        await sendCryptoViewModel.loadFastVault(tx: tx, vault: vault)
        
        await MainActor.run {
            isLoading = false
            router.navigate(to: SendRoute.verify(tx: tx, vault: vault))
        }
    }
}
