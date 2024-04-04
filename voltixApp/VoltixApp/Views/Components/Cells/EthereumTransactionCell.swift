//
//  EthereumTransactionCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-27.
//

import SwiftUI

struct EthereumTransactionCell: View {
    let chain: Chain?
    let transaction: EtherscanAPITransactionDetail
    let myAddress: String
    @ObservedObject var etherScanService: EtherScanService
    
    @State var isSent = true
    
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
        .onAppear {
            print(transaction)
            setData()
        }
    }
    
    var transactionIDCell: some View {
        let hash = transaction.hash ?? ""
        let url = Endpoint.getExplorerURL(chainTicker: getTokenSymbol(), txid: hash)
        let image = isSent ? "arrow.up.circle" : "arrow.down.circle"
        
        return TransactionCell(
            title: "transactionID",
            id: hash,
            url: url,
            image: image
        )
    }
    
    var fromCell: some View {
        let address = transaction.from
        let id = isSent ? selfText : address
        let url = Endpoint.getExplorerByAddressURL(chainTicker: getTokenSymbol(), address: address) ?? ""
        
        return TransactionCell(
            title: "from",
            id: id,
            url: url
        )
    }
    
    var toCell: some View {
        let address = transaction.to
        let id = isSent ? address : selfText
        let url = Endpoint.getExplorerByAddressURL(chainTicker: getTokenSymbol(), address: address) ?? ""
        
        return TransactionCell(
            title: "to",
            id: id,
            url: url
        )
    }
    
    var summary: some View {
        VStack(spacing: 12) {
            amountCell
            Separator()
            feesCell
        }
    }
    
    var amountCell: some View {
        let decimals: Int = Int(transaction.tokenDecimal ?? "\(EVMHelper.ethDecimals)") ?? EVMHelper.ethDecimals
        let etherValue = etherScanService.convertToEther(fromWei: transaction.value, decimals)
        let tokenSymbol = transaction.tokenSymbol ?? getTokenSymbol()
        
        return getSummaryCell(title: "amount", value: "\(etherValue) \(tokenSymbol)")
    }
    
    var feesCell: some View {
        let feeDisplay = etherScanService.calculateTransactionFee(
            gasUsed: transaction.gasUsed ?? "",
            gasPrice: transaction.gasPrice
        )
        
        return getSummaryCell(title: "gas", value: "\(feeDisplay) \(getTokenSymbol())")
    }
    
    private func setData() {
        isSent = myAddress.lowercased() != transaction.to.lowercased()
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
    
    private func getTokenSymbol() -> String {
        return chain?.ticker ?? ""
    }
}
