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
    
    @State var isButtonDisabled = false
    
    let vault: Vault
    
    @State var fastPasswordPresented = false

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
                
                if sendCryptoVerifyViewModel.blowfishShow {
                    blowfishView
                }
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
            FilledButton(title: NSLocalizedString("fastSign", comment: ""))
        }
        .disabled(!sendCryptoVerifyViewModel.isValidForm)
        .opacity(!sendCryptoVerifyViewModel.isValidForm ? 0.5 : 1)
        .padding(.horizontal, 16)
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
        .disabled(!sendCryptoVerifyViewModel.isValidForm)
        .opacity(!sendCryptoVerifyViewModel.isValidForm ? 0.5 : 1)
        .padding(.horizontal, 16)
    }
    
    private func setData() {
        isButtonDisabled = false
        
        Task {
            do {
                try await sendCryptoVerifyViewModel.blowfishTransactionScan(tx: tx, vault: vault)
                blowfishViewModel.updateResponse(sendCryptoVerifyViewModel.blowfishWarnings)
            } catch {
                print("Error scanning transaction: \(error)")
            }
        }
    }

    private func signPressed() {
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
