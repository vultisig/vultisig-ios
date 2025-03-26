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
                summary
                checkboxes
            }
            .padding(.horizontal, 16)
        }
    }

    var summary: some View {
        VStack(spacing: 16) {
            getValueCell(
                for: "fromAsset",
                with: getFromAmount()
            )
            
            Separator()
            getValueCell(
                for: "toAsset",
                with: getToAmount()
            )
            
            if swapViewModel.showAllowance(tx: tx) {
                Separator()
                getValueCell(
                    for: "Allowance",
                    with: getFromAmount()
                )
            }
            
            if swapViewModel.showFees(tx: tx) {
                Separator()
                getValueCell(
                    for: "swapFee",
                    with: swapViewModel.swapFeeString(tx: tx),
                    isVertical: false
                )
            }
            
            if swapViewModel.showGas(tx: tx) {
                Separator()
                getValueCell(
                    for: "networkFee",
                    with: "\(swapViewModel.swapGasString(tx: tx))(~\(swapViewModel.approveFeeString(tx: tx)))",
                    isVertical: false
                )
            }
            
            if swapViewModel.showTotalFees(tx: tx) {
                Separator()
                getValueCell(
                    for: "totalFee",
                    with: "\(swapViewModel.totalFeeString(tx: tx))",
                    isVertical: false
                )
            }
        }
        .padding(16)
        .background(Color.blue600)
        .cornerRadius(10)
    }

    var checkboxes: some View {
        VStack(spacing: 16) {
            Checkbox(isChecked: $verifyViewModel.isAmountCorrect, text: "The swap amount is correct")
            Checkbox(isChecked: $verifyViewModel.isFeeCorrect, text: "I agree with the amount I will receive after the swap.")
            if showApproveCheckmark {
                Checkbox(isChecked: $verifyViewModel.isApproveCorrect, text: "I agree with providing ERC20 allowance for exact swap amount")
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
        .padding(.horizontal, 40)
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
        .padding(.horizontal, 40)
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

    func getFromAmount() -> String {
        if tx.fromCoin.chain == tx.toCoin.chain {
            return "\(tx.fromAmount) \(tx.fromCoin.ticker)"
        } else {
            return "\(tx.fromAmount) \(tx.fromCoin.ticker) (\(tx.fromCoin.chain.ticker))"
        }
    }

    func getToAmount() -> String {
        if tx.fromCoin.chain == tx.toCoin.chain {
            return "\(tx.toAmountDecimal.description) \(tx.toCoin.ticker)"
        } else {
            return "\(tx.toAmountDecimal.description) \(tx.toCoin.ticker) (\(tx.toCoin.chain.ticker))"
        }
    }

    func getValueCell(for title: String, with value: String, isVertical: Bool = true) -> some View {
        ZStack {
            if isVertical {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString(title, comment: ""))
                        .font(.body20MontserratSemiBold)
                        .foregroundColor(.neutral0)

                    Text(value)
                        .font(.body13MenloBold)
                        .foregroundColor(.turquoise600)
                }
            } else {
                HStack {
                    Text(NSLocalizedString(title, comment: ""))
                    Spacer()
                    Text(value)
                    
                }
                .font(.body16MontserratBold)
                .foregroundColor(.neutral0)
            }
        }
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
}

#Preview {
    SwapVerifyView(
        tx: SwapTransaction(),
        swapViewModel: SwapCryptoViewModel(),
        vault: Vault.example
    )
    .environmentObject(SettingsViewModel())
}
