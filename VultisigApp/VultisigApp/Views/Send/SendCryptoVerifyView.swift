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
    @StateObject private var blowfishViewModel = BlowfishWarningViewModel()
    
    let vault: Vault
    
    @State var isLoading = true
    @State var fastPasswordPresented = false

    var body: some View {
        ZStack {
            Background()
            view
            if isLoading {
                Loader()
            }
        }
        .gesture(DragGesture())
        .alert(isPresented: $sendCryptoVerifyViewModel.showAlert) {
            alert
        }
        .onDisappear {
            sendCryptoVerifyViewModel.isLoading = false
        }
        .onAppear {
            isLoading = true
            Task {
                do {
                    try await sendCryptoVerifyViewModel.blowfishTransactionScan(tx: tx, vault: vault)
                    blowfishViewModel.updateResponse(sendCryptoVerifyViewModel.blowfishWarnings)
                    isLoading = false
                } catch {
                    print("Error scanning transaction: \(error)")
                    isLoading = false
                }
            }
        }
    }
    
    var blowfishView: some View {
        BlowfishWarningInformationNote(viewModel: blowfishViewModel)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }
    
    var view: some View {
        container
    }
    
    var content: some View {
        VStack(spacing: 16) {
            fields
            if sendCryptoVerifyViewModel.blowfishShow {
                blowfishView
            }
            if tx.isFastVault {
                fastVaultButton
            }
            pairedSignButton
        }
        .blur(radius: sendCryptoVerifyViewModel.isLoading ? 1 : 0)
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
            }
            .padding(.horizontal, 16)
        }
    }
    
    var summary: some View {
        VStack(spacing: 16) {
            getAddressCell(for: "from", with: tx.fromAddress)
            Separator()
            getAddressCell(for: "to", with: tx.toAddress)
            Separator()
            getDetailsCell(for: "amount", with: getAmount())
            Separator()
            getDetailsCell(for: "amount(inFiat)", with: getFiatAmount())
            
            if !tx.memo.isEmpty {
                Separator()
                getDetailsCell(for: "memo", with: tx.memo)
            }
            
            if tx.sendMaxAmount {
                Separator()
                getDetailsCell(for: "Max Amount", with: tx.sendMaxAmount.description)
            }
            
            Separator()
            getDetailsCell(for: "gas", with: tx.gasInReadable)
        }
        .padding(16)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    var checkboxes: some View {
        VStack(spacing: 16) {
            Checkbox(isChecked: $sendCryptoVerifyViewModel.isAddressCorrect, text: "sendingRightAddressCheck")
            Checkbox(isChecked: $sendCryptoVerifyViewModel.isAmountCorrect, text: "correctAmountCheck")
            Checkbox(isChecked: $sendCryptoVerifyViewModel.isHackedOrPhished, text: "notHackedCheck")
        }
    }
    
    var fastVaultButton: some View {
        Button {
            fastPasswordPresented = true
        } label: {
            FilledButton(title: "Fast Sign")
        }
        .padding(.horizontal, 40)
        .sheet(isPresented: $fastPasswordPresented) {
            FastVaultEnterPasswordView(
                password: $tx.fastVaultPassword,
                onSubmit: { signPressed() }
            )
        }
    }

    var pairedSignButton: some View {
        Button {
            signPressed()
        } label: {
            OutlineButton(title: tx.isFastVault ? "Paired sign" : "sign")
        }
        .padding(.horizontal, 40)
    }

    private func signPressed() {
        sendCryptoVerifyViewModel.isLoading = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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

    private func getAddressCell(for title: String, with address: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString(title, comment: ""))
                .font(.body20MontserratSemiBold)
                .foregroundColor(.neutral0)
            
            Text(address)
                .font(.body12Menlo)
                .foregroundColor(.turquoise600)
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
    
    private func getAmount() -> String {
        tx.amount + " " + tx.coin.ticker
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
}
