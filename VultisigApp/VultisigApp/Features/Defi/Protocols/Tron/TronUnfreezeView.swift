//
//  TronUnfreezeView.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI
import BigInt

struct TronUnfreezeView: View {
    let vault: Vault
    @StateObject private var model: TronViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.router) var router
    
    @State var amount: String = ""
    @State var percentage: Double = 0.0
    @State var isLoading = false
    @State var error: Error?
    @State var isFastVault = false
    @State var fastPasswordPresented = false
    @State var fastVaultPassword: String = ""
    @State var selectedResourceType: TronResourceType = .bandwidth
    
    @StateObject var sendTransaction = SendTransaction()
    
    init(vault: Vault, model: TronViewModel) {
        self.vault = vault
        self._model = StateObject(wrappedValue: model)
    }
    
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
                Color.black.opacity(0.5).ignoresSafeArea()
                ProgressView()
            }
        }
        .task {
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
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            
            Spacer()
            
            Text(NSLocalizedString("tronUnfreezeTitle", comment: "Unfreeze TRX"))
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
                    .font(.caption)
            }
            
            unfreezeButton
        }
        .padding(TronConstants.Design.horizontalPadding)
        .background(Theme.colors.bgPrimary)
    }
    
    var scrollableContent: some View {
        VStack(spacing: TronConstants.Design.verticalSpacing) {
            // Resource Type Picker
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("tronResourceType", comment: "Resource Type"))
                    .font(TronConstants.Fonts.subtitle)
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
                    Text(NSLocalizedString("tronUnfreezeAmount", comment: "Amount"))
                        .font(TronConstants.Fonts.subtitle)
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
                        .font(TronConstants.Fonts.subtitle)
                        .foregroundStyle(Theme.colors.textSecondary)
                }
                
                Spacer()
                
                VStack(spacing: TronConstants.Design.verticalSpacing) {
                    Slider(value: Binding(
                        get: { percentage },
                        set: { newValue in
                            percentage = newValue
                            updateAmount(from: newValue)
                        }
                    ), in: 0...100)
                    .accentColor(Theme.colors.primaryAccent1)
                    
                    HStack {
                        Text(NSLocalizedString("tronUnfreezeBalanceAvailable", comment: "Frozen balance:"))
                            .font(TronConstants.Fonts.subtitle)
                            .foregroundStyle(Theme.colors.textSecondary)
                        
                        Spacer()
                        
                        Text("\(frozenBalanceForSelectedType.formatted()) TRX")
                            .font(TronConstants.Fonts.subtitle)
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
    
    @ViewBuilder
    var unfreezeButton: some View {
        if isFastVault {
            VStack {
                Text(NSLocalizedString("holdForPairedSign", comment: ""))
                    .foregroundColor(Theme.colors.textTertiary)
                    .font(Theme.fonts.bodySMedium)
                
                LongPressPrimaryButton(title: NSLocalizedString("tronUnfreezeConfirm", comment: "Continue")) {
                    fastPasswordPresented = true
                } longPressAction: {
                    fastVaultPassword = ""
                    Task { await handleUnfreeze() }
                }
            }
            .disabled(isButtonDisabled)
        } else {
            PrimaryButton(title: NSLocalizedString("tronUnfreezeConfirm", comment: "Continue")) {
                Task { await handleUnfreeze() }
            }
            .disabled(isButtonDisabled)
        }
    }
    
    var frozenBalanceForSelectedType: Decimal {
        switch selectedResourceType {
        case .bandwidth:
            return model.frozenBandwidthBalance
        case .energy:
            return model.frozenEnergyBalance
        }
    }
    
    var isButtonDisabled: Bool {
        amount.isEmpty || (Decimal(string: amount) ?? 0) <= 0 || (Decimal(string: amount) ?? 0) > frozenBalanceForSelectedType || isLoading
    }
    
    func loadFastVaultStatus() async {
        let isExist = await FastVaultService.shared.exist(pubKeyECDSA: vault.pubKeyECDSA)
        let isLocalBackup = vault.localPartyID.lowercased().contains("server-")
        
        await MainActor.run {
            isFastVault = isExist && !isLocalBackup
        }
    }
    
    func updatePercentage(from amountStr: String) async {
        let balance = frozenBalanceForSelectedType
        guard let amountDec = Decimal(string: amountStr), balance > 0 else {
            return
        }
        let percent = (amountDec / balance) * 100
        let cappedPercent = min(Double(truncating: percent as NSNumber), 100.0)
        
        if abs(self.percentage - cappedPercent) > 0.1 {
            await MainActor.run {
                self.percentage = cappedPercent
            }
        }
    }
    
    func updateAmount(from percent: Double) {
        let balance = frozenBalanceForSelectedType
        guard balance > 0 else { return }
        let amountDec = balance * Decimal(percent) / 100
        let newAmount = amountDec.truncated(toPlaces: 6).description
        if self.amount != newAmount {
            self.amount = newAmount
        }
    }
    
    func handleUnfreeze() async {
        guard let amountDecimal = Decimal(string: amount) else {
            await MainActor.run {
                isLoading = false
            }
            return
        }
        
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            let decimals = 6
            let amountUnits = (amountDecimal * pow(10, decimals)).description
            let cleanAmountUnits = amountUnits.components(separatedBy: ".").first ?? amountUnits
            let amountVal = BigInt(cleanAmountUnits) ?? BigInt(0)
            
            let payload = try await model.logic.getUnfreezePayload(
                vault: vault,
                amount: amountVal,
                resourceType: selectedResourceType
            )
            
            guard let trxCoin = TronViewLogic.getTrxCoin(vault: vault) else {
                throw TronStakingError.noTrxCoin
            }
            
            await MainActor.run {
                self.sendTransaction.reset(coin: trxCoin)
                self.sendTransaction.isFastVault = isFastVault
                self.sendTransaction.fastVaultPassword = fastVaultPassword
                
                router.navigate(
                    to: SendRoute.pairing(
                        vault: vault,
                        tx: sendTransaction,
                        keysignPayload: payload,
                        fastVaultPassword: fastVaultPassword.nilIfEmpty
                    )
                )
                
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
