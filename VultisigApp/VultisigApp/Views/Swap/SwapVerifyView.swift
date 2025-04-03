//
//  SwapVerifyView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 08.04.2024.
//

import SwiftUI

struct SwapVerifyView: View {
    @StateObject var verifyViewModel = SwapCryptoVerifyViewModel()

    @ObservedObject var tx: SwapTransaction
    @ObservedObject var swapViewModel: SwapCryptoViewModel

    let vault: Vault

    @State var fastPasswordPresented = false
    
    @EnvironmentObject var settingsViewModel: SettingsViewModel

    var body: some View {
        ZStack {
            Background()
            view

            if swapViewModel.isLoading {
                Loader()
            }
        }
        .onDisappear {
            swapViewModel.isLoading = false
        }
    }

    var view: some View {
        container
    }
    
    var content: some View {
        VStack(spacing: 16) {
            fields
            if tx.isFastVault {
                fastVaultButton
            }
            pairedSignButton
        }
    }

    var fields: some View {
        ScrollView {
            VStack(spacing: 30) {
                Spacer()
                summary
                checkboxes
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }

    var summary: some View {
        VStack(spacing: 16) {
            summaryTitle
            
            getSwapAssetCell(
                for: tx.fromAmount,
                with: tx.fromCoin.ticker,
                on: tx.fromCoin.chain
            )
            
            separator
            getSwapAssetCell(
                for: tx.toAmountDecimal.description,
                with: tx.toCoin.ticker,
                on: tx.toCoin.chain
            )
            
            if let providerName = tx.quote?.displayName {
                separator
                getValueCell(
                    for: "provider",
                    with: providerName,
                    showIcon: true
                )
            }
            
            if swapViewModel.showGas(tx: tx) {
                separator
                getValueCell(
                    for: "networkFee",
                    with: swapViewModel.swapGasString(tx: tx),
                    bracketValue: swapViewModel.approveFeeString(tx: tx)
                )
            }
            
            if swapViewModel.showFees(tx: tx) {
                separator
                getValueCell(
                    for: "swapFee",
                    with: swapViewModel.swapFeeString(tx: tx)
                )
            }
            
            if swapViewModel.showTotalFees(tx: tx) {
                separator
                getValueCell(
                    for: "maxTotalFee",
                    with: swapViewModel.totalFeeString(tx: tx)
                )
            }
        }
        .padding(16)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    var summaryTitle: some View {
        Text(NSLocalizedString("youreWwapping", comment: ""))
            .font(.body16BrockmannMedium)
            .foregroundColor(.lightText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var checkboxes: some View {
        VStack(spacing: 16) {
            Checkbox(isChecked: $verifyViewModel.isAmountCorrect, text: "swapVerifyCheckbox1Description")
            Checkbox(isChecked: $verifyViewModel.isFeeCorrect, text: "swapVerifyCheckbox2Description")
            if showApproveCheckmark {
                Checkbox(isChecked: $verifyViewModel.isApproveCorrect, text: "swapVerifyCheckbox3Description")
            }
        }
    }

    var fastVaultButton: some View {
        Button {
            fastPasswordPresented = true
        } label: {
            FilledButton(title: NSLocalizedString("fastSign", comment: ""))
        }
        .disabled(!verifyViewModel.isValidForm(shouldApprove: tx.isApproveRequired))
        .opacity(verifyViewModel.isValidForm(shouldApprove: tx.isApproveRequired) ? 1 : 0.5)
        .padding(.horizontal, 24)
        .sheet(isPresented: $fastPasswordPresented) {
            FastVaultEnterPasswordView(
                password: $tx.fastVaultPassword,
                vault: vault, 
                onSubmit: { signPressed() }
            )
        }
    }

    var pairedSignButton: some View {
        Button {
            signPressed()
        } label: {
            if tx.isFastVault {
                OutlineButton(title: "Paired sign")
            } else {
                FilledButton(title: "sign")
            }
            
        }
        .disabled(!verifyViewModel.isValidForm(shouldApprove: tx.isApproveRequired))
        .opacity(verifyViewModel.isValidForm(shouldApprove: tx.isApproveRequired) ? 1 : 0.5)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    func signPressed() {
        Task {
            if await swapViewModel.buildSwapKeysignPayload(tx: tx, vault: vault) {
                swapViewModel.moveToNextView()
            }
        }
    }

    var showApproveCheckmark: Bool {
        return tx.isApproveRequired
    }
    
    var separator: some View {
        Separator()
            .opacity(0.2)
    }

    func getValueCell(
        for title: String,
        with value: String,
        bracketValue: String? = nil,
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
            
            Text(value)
                .foregroundColor(.neutral0)
            
            if let bracketValue {
                Group {
                    Text("(") +
                    Text(bracketValue) +
                    Text(")")
                }
                .foregroundColor(.extraLightGray)
            }
            
        }
        .font(.body14BrockmannMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func getDetailsCell(for title: String, with value: String) -> some View {
        HStack {
            Text(
                NSLocalizedString(title, comment: "")
                    .replacingOccurrences(of: "Fiat", with: SettingsCurrency.current.rawValue)
            )
            Spacer()
            Text(value)
        }
        .font(.body16MenloBold)
        .foregroundColor(.neutral100)
    }
    
    private func getSwapAssetCell(
        for amount: String,
        with ticker: String,
        on chain: Chain? = nil
    ) -> some View {
        VStack(spacing: 4) {
            Group {
                Text(amount)
                    .foregroundColor(.neutral0) +
                Text(" ") +
                Text(ticker)
                    .foregroundColor(.extraLightGray)
            }
            .font(.body18BrockmannMedium)
            
            if let chain {
                HStack(spacing: 2) {
                    Text(NSLocalizedString("on", comment: ""))
                        .foregroundColor(.extraLightGray)
                        .padding(.trailing, 4)
                    
                    Image(chain.logo)
                        .resizable()
                        .frame(width: 12, height: 12)
                    
                    Text(chain.name)
                        .foregroundColor(.neutral0)
                }
                .font(.body10BrockmannMedium)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    SwapVerifyView(
        tx: SwapTransaction(),
        swapViewModel: SwapCryptoViewModel(),
        vault: Vault.example
    )
    .environmentObject(SettingsViewModel())
}
