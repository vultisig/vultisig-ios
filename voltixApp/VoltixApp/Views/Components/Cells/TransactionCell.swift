//
//  TransactionCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-26.
//

import SwiftUI

struct TransactionCell: View {
    @State var isReceiving = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            transactionIDField
            Separator()
            addressField
            Separator()
            summary
        }
        .padding(16)
        .background(Color.blue600)
    }
    
    var transactionIDField: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            txID
        }
    }
    
    var header: some View {
        HStack(spacing: 12) {
            Image(systemName: isReceiving ? "arrow.down.circle" : "arrow.up.circle")
            Text(NSLocalizedString("transactionID", comment: "Transaction ID"))
        }
        .font(.body20MontserratSemiBold)
        .foregroundColor(.neutral0)
    }
    
    var txID: some View {
        Text("0xF42b6DE07e40cb1D4a24292bB89862f599Ac5")
            .font(.body13Menlo)
            .foregroundColor(.turquoise600)
    }
    
    var addressField: some View {
        VStack(alignment: .leading, spacing: 8) {
            addressTitle
            address
        }
    }
    
    var addressTitle: some View {
        Text(NSLocalizedString(isReceiving ? "from" : "to", comment: ""))
            .font(.body20MontserratSemiBold)
            .foregroundColor(.neutral0)
    }
    
    var address: some View {
        Text("0xF42b6DE07e40cb1D4a24292bB89862f599Ac5")
            .font(.body13Menlo)
            .foregroundColor(.turquoise600)
    }
    
    var summary: some View {
        VStack(spacing: 12) {
            getSummaryCell(title: "amount", value: "1.0 ETH")
            Separator()
            getSummaryCell(title: "Memo", value: "")
            Separator()
            getSummaryCell(title: "gas", value: "$4.00")
        }
    }
    
    private func getSummaryCell(title: String, value: String) -> some View {
        HStack {
            Text(NSLocalizedString(title, comment: ""))
            Spacer()
            Text(value)
        }
        .frame(height: 32)
        .font(.body16MenloBold)
        .foregroundColor(.neutral0)
    }
}

#Preview {
    TransactionCell()
}
