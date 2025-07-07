//
//  SendCryptoVerifyView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct SendCryptoVerifyView: View {
    @Binding var keysignPayload: KeysignPayload?
    
    @ObservedObject var sendCryptoViewModel: SendCryptoViewModel
    @ObservedObject var sendCryptoVerifyViewModel: SendCryptoVerifyViewModel
    @ObservedObject var tx: SendTransaction
    
    let vault: Vault
    
    @State var isButtonDisabled = false
    @State var fastPasswordPresented = false
    
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .gesture(DragGesture())
        .alert(isPresented: $sendCryptoVerifyViewModel.showAlert) {
            alert
        }
        .onDisappear {
            sendCryptoVerifyViewModel.isLoading = false
        }
        .onAppear {
            setData()
        }
        .task {
            await sendCryptoVerifyViewModel.performSecurityScan(tx: tx)
        }
    }
    
    var view: some View {
        container
    }
    
    var content: some View {
        VStack(spacing: 16) {
            blockAidBanner
            fields
            
            if tx.isFastVault {
                fastVaultButton
            }
            
            pairedSignButton
        }
        .blur(radius: sendCryptoVerifyViewModel.isLoading ? 1 : 0)
    }
    
    var blockAidBanner: some View {
        Image("blockaidScannedBanner")
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("error", comment: "")),
            message: Text(NSLocalizedString(sendCryptoVerifyViewModel.errorMessage, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    var fields: some View {
        ScrollView {
            VStack(spacing: 30) {
                summary
                checkboxes
                
                if sendCryptoVerifyViewModel.showSecurityScan {
                    SecurityScanView(viewModel: sendCryptoVerifyViewModel.securityScanViewModel)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    var summary: some View {
        VStack(spacing: 16) {
            summaryTitle
            summaryCoinDetails
            Separator()
            getValueCell(for: "from", with: vault.name, bracketValue: tx.fromAddress)
            Separator()
            getValueCell(for: "to", with: tx.toAddress)
            Separator()
            getValueCell(for: "network", with: tx.coin.chain.name, showIcon: true)
            Separator()
            
            if !tx.memo.isEmpty {
                getValueCell(for: "memo", with: tx.memo)
                Separator()
            }
            
            getValueCell(for: "estNetworkFee", with: tx.gasInReadable, secondRowText: sendCryptoViewModel.feesInReadable(tx: tx, vault: vault))
        }
        .padding(16)
        .background(Color.blue600)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(LinearGradient.borderGreen, lineWidth: 1)
        )
        .padding(1)
    }
    
    var summaryTitle: some View {
        Text(NSLocalizedString("youreSending", comment: ""))
            .foregroundColor(.lightText)
            .font(.body16BrockmannMedium)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var summaryCoinDetails: some View {
        HStack(spacing: 8) {
            Image(tx.coin.chain.logo)
                .resizable()
                .frame(width: 24, height: 24)
                .cornerRadius(32)
            
            Text(tx.amount)
                .foregroundColor(.neutral0)
            
            Text(tx.coin.ticker)
                .foregroundColor(.extraLightGray)
            
            Spacer()
        }
        .font(.body18BrockmannMedium)
    }
    
    var checkboxes: some View {
        VStack(spacing: 16) {
            
            Checkbox(isChecked: $sendCryptoVerifyViewModel.isAmountCorrect, text: "correctAmountCheck")
            Checkbox(isChecked: $sendCryptoVerifyViewModel.isAddressCorrect, text: "sendingRightAddressCheck")
        }
    }
    
    private func setData() {
        isButtonDisabled = false
    }
    
    func signPressed() {
        guard !isButtonDisabled else {
            return
        }
        
        isButtonDisabled = true
        sendCryptoVerifyViewModel.isLoading = true
        
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            Task {
                keysignPayload = await sendCryptoVerifyViewModel.validateForm(
                    tx: tx,
                    vault: vault
                )
                
                if keysignPayload != nil {
                    sendCryptoViewModel.moveToNextView()
                }
            }
        }
    }
    
    func getValueCell(
        for title: String,
        with value: String,
        bracketValue: String? = nil,
        secondRowText: String? = nil,
        showIcon: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            Text(NSLocalizedString(title, comment: ""))
                .foregroundColor(.extraLightGray)
            
            Spacer()
            
            if showIcon {
                Image(value)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            
            VStack(alignment: .trailing) {
                Text(value)
                    .foregroundColor(.neutral0)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                if let secondRowText {
                    Text(secondRowText)
                        .foregroundColor(.extraLightGray)
                }
            }
            
            if let bracketValue {
                Group {
                    Text("(") +
                    Text(bracketValue) +
                    Text(")")
                }
                .foregroundColor(.extraLightGray)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            
        }
        .font(.body14BrockmannMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func getAmount() -> String {
        tx.amount.formatToDecimal(digits: 8) + " " + tx.coin.ticker
    }
    
    private func getFiatAmount() -> String {
        tx.amountInFiat.formatToFiat()
    }
}

#Preview {
    SendCryptoVerifyView(
        keysignPayload: .constant(nil),
        sendCryptoViewModel: SendCryptoViewModel(),
        sendCryptoVerifyViewModel: SendCryptoVerifyViewModel(),
        tx: SendTransaction(),
        vault: Vault.example
    )
    .environmentObject(SettingsViewModel())
}
