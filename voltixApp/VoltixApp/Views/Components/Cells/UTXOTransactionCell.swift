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
    @ObservedObject var utxoTransactionsService: UTXOTransactionsService
    
    let selfText = NSLocalizedString("self", comment: "")
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            transactionIDCell
            Separator()
            fromCell
            Separator()
            toCell
            Separator()
            summary
        }
        .padding(16)
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }
    
    var transactionIDCell: some View {
        let id = transaction.txid
        let url = Endpoint.getExplorerURL(chainTicker: tx.coin.ticker, txid: id)
        let image = transaction.isSent ? "arrow.up.circle" : "arrow.down.circle"
        
        return TransactionCell(
            title: "transactionID",
            id: id,
            url: url,
            image: image
        )
    }
    
    var fromCell: some View {
        var address = ""
        var id = ""
        
        if transaction.isSent {
            id = selfText
            address = transaction.sentTo.first ?? ""
        } else if transaction.isReceived {
            id = transaction.receivedFrom.first ?? ""
            address = id
        }
        
        let url = Endpoint.getExplorerByAddressURL(chainTicker: tx.coin.ticker, address: address) ?? ""
        
        return TransactionCell(
            title: "from",
            id: id,
            url: url
        )
    }
    
    var toCell: some View {
        var address = ""
        var id = ""
        
        if transaction.isSent {
            id = transaction.sentTo.first ?? ""
            address = id
        } else if transaction.isReceived {
            id = selfText
            address = transaction.receivedFrom.first ?? ""
        }
        
        let url = Endpoint.getExplorerByAddressURL(chainTicker: tx.coin.ticker, address: address) ?? ""
        
        return TransactionCell(
            title: "to",
            id: id,
            url: url
        )
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
        getSummaryCell(
            title: "amount",
            value: utxoTransactionsService.getAmount(for: transaction, tx: tx)
        )
    }
    
    var memoCell: some View {
        VStack(spacing: 12) {
            Separator()
            getSummaryCell(title: "Memo", value: transaction.opReturnData ?? "-")
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
