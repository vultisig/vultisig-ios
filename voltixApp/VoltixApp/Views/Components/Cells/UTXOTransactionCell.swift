//
//  UTXOTransactionCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-26.
//

import SwiftUI

struct UTXOTransactionCell: View {
    let transaction: UTXOTransactionMempool
    let tx: SendTransaction
    
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
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }
    
    var transactionIDField: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            txID
        }
    }
    
    var header: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.isSent ? "arrow.up.circle" : "arrow.down.circle")
            Text(NSLocalizedString("transactionID", comment: "Transaction ID"))
        }
        .font(.body20MontserratSemiBold)
        .foregroundColor(.neutral0)
    }
    
    var txID: some View {
        Text(transaction.txid)
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
        Text(NSLocalizedString(transaction.isSent ? "to" : "from", comment: ""))
            .font(.body20MontserratSemiBold)
            .foregroundColor(.neutral0)
    }
    
    var address: some View {
        var address: String? = ""
        
        if transaction.isSent {
            address = transaction.sentTo.first
        } else if transaction.isReceived {
            address = transaction.receivedFrom.first
        }
        
        return Text(address ?? "")
            .font(.body13Menlo)
            .foregroundColor(.turquoise600)
    }
    
    var summary: some View {
        VStack(spacing: 12) {
            amountCell
            
            if transaction.opReturnData != nil {
                memoCell
            }
            
            Separator()
            getSummaryCell(title: "gas", value: "$4.00")
        }
    }
    
    var amountCell: some View {
        getSummaryCell(title: "amount", value: getAmount())
    }
    
    var memoCell: some View {
        VStack(spacing: 12) {
            Separator()
            getSummaryCell(title: "Memo", value: transaction.opReturnData ?? "")
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
    
    private func getAmount() -> String {
        if transaction.isSent {
            return formatAmount(transaction.amountSent)
        } else if transaction.isReceived {
            return formatAmount(transaction.amountReceived)
        }
        return ""
    }
    
    private func formatAmount(_ amountSatoshis: Int) -> String {
        let amountBTC = Double(amountSatoshis) / 100_000_000 // Convert satoshis to BTC
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0 // Minimum number of digits after the decimal point
        formatter.maximumFractionDigits = 8 // Maximum number of digits after the decimal point, adjust if needed
        formatter.decimalSeparator = "." // Use dot for decimal separation
        formatter.groupingSeparator = "," // Use comma for thousands separation, adjust if needed
        
        return (formatter.string(from: NSNumber(value: amountBTC)) ?? "\(amountBTC) \(tx.coin.ticker.uppercased())")
    }
}
