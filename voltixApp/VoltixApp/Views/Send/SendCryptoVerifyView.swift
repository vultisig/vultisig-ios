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
    
    @State var isAddressCorrect = false
    @State var isAmountCorrect = false
    @State var isHackedOrPhished = false
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .gesture(DragGesture())
        .onAppear {
            reloadTransactions()
        }
    }
    
    var view: some View {
        VStack {
            fields
            button
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
            getAddressCell(for: "from", with: "0xF42b6DE07e40cb1D4a24292bB89862f599Ac5")
            Separator()
            getAddressCell(for: "to", with: "0xF42b6DE07e40cb1D4a24292bB89862f599Ac5")
            Separator()
            getDetailsCell(for: "amount", with: "1.0 ETH")
            Separator()
            getDetailsCell(for: "memo", with: "")
            Separator()
            getDetailsCell(for: "gas", with: "$4.00")
        }
        .padding(16)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    var checkboxes: some View {
        VStack(spacing: 16) {
            Checkbox(isChecked: $isAddressCorrect, text: "sendingRightAddressCheck")
            Checkbox(isChecked: $isAmountCorrect, text: "correctAmountCheck")
            Checkbox(isChecked: $isHackedOrPhished, text: "notHackedCheck")
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
    
    func getAddressCell(for title: String, with address: String) -> some View {
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
    
    func getDetailsCell(for title: String, with value: String) -> some View {
        HStack {
            Text(NSLocalizedString(title, comment: ""))
            Spacer()
            Text(value)
        }
        .font(.body16MenloBold)
        .foregroundColor(.neutral100)
    }
    
    private func reloadTransactions() {
//        sendCryptoVerifyViewModel.r
    }
}

#Preview {
    SendCryptoVerifyView(sendCryptoViewModel: SendCryptoViewModel(), sendCryptoVerifyViewModel: SendCryptoVerifyViewModel())
}
