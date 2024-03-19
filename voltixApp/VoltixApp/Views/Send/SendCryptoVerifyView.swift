//
//  SendCryptoVerifyView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct SendCryptoVerifyView: View {
    @ObservedObject var sendCryptoViewModel: SendCryptoViewModel
    @ObservedObject var sendCryptoVerifyViewModel: SendCryptoVerifyViewModel
    @ObservedObject var tx: SendTransaction
    @ObservedObject var utxoBtc: BitcoinUnspentOutputsService
    @ObservedObject var utxoLtc: LitecoinUnspentOutputsService
    @ObservedObject var eth: EthplorerAPIService
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .gesture(DragGesture())
        .onAppear {
            reloadTransactions()
        }
        .alert(isPresented: $sendCryptoVerifyViewModel.showAlert) {
            alert
        }
    }
    
    var view: some View {
        VStack {
            fields
            button
        }
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("error", comment: "")),
            message: Text(sendCryptoVerifyViewModel.errorMessage),
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
            getDetailsCell(for: "amount(inUSD)", with: getUSDAmount())
            Separator()
            getDetailsCell(for: "memo", with: tx.memo)
            Separator()
            getDetailsCell(for: "gas", with: getGasAmount())
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
    
    var button: some View {
        Button {
            sendCryptoViewModel.moveToNextView()
        } label: {
            FilledButton(title: "sign")
        }
        .padding(40)
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
            Text(NSLocalizedString(title, comment: ""))
            Spacer()
            Text(value)
        }
        .font(.body16MenloBold)
        .foregroundColor(.neutral100)
    }
    
    private func reloadTransactions() {
        sendCryptoVerifyViewModel.reloadTransactions(
            tx: tx,
            utxoBtc: utxoBtc,
            utxoLtc: utxoLtc,
            eth: eth
        )
    }
    
    private func getAmount() -> String {
        tx.amount + " " + tx.coin.ticker
    }
    
    private func getUSDAmount() -> String {
        "$" + tx.amountInUSD
    }
    
    private func getGasAmount() -> String {
        tx.gas + " " + tx.coin.feeUnit
    }
}

#Preview {
    SendCryptoVerifyView(
        sendCryptoViewModel: SendCryptoViewModel(),
        sendCryptoVerifyViewModel: SendCryptoVerifyViewModel(),
        tx: SendTransaction(),
        utxoBtc: BitcoinUnspentOutputsService(),
        utxoLtc: LitecoinUnspentOutputsService(),
        eth: EthplorerAPIService()
    )
}
