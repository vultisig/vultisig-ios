//
//  TransactionDetailsViewModel.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 13/02/2024.
//

import Foundation

import CodeScanner
import OSLog
import SwiftUI
import UniformTypeIdentifiers
import WalletCore

class SendTransaction: ObservableObject, Hashable {
    

    init() {
        self.toAddress = ""
        self.amount = ""
        self.memo = ""
        self.gas = ""
    }
    
    init(toAddress: String, amount: String, memo: String, gas: String) {
        self.toAddress = toAddress
        self.amount = amount
        self.memo = memo
        self.gas = gas
    }
    
    init(toAddress: String, amount: String, memo: String, gas: String, coin: Coin) {
        self.toAddress = toAddress
        self.amount = amount
        self.memo = memo
        self.gas = gas
        self.coin = coin
    }
    
    static func == (lhs: SendTransaction, rhs: SendTransaction) -> Bool {
        return lhs.fromAddress == rhs.fromAddress &&
        lhs.toAddress == rhs.toAddress &&
        lhs.amount == rhs.amount &&
        lhs.memo == rhs.memo &&
        lhs.gas == rhs.gas
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(fromAddress)
        hasher.combine(toAddress)
        hasher.combine(amount)
        hasher.combine(memo)
        hasher.combine(gas)
    }
    
    var fromAddress: String {
        return coin.address
    }
    @Published var toAddress: String = ""
    @Published var amount: String = ""
    @Published var memo: String = ""
    @Published var gas: String = ""
    @Published var coin: Coin = Coin(chain: Chain.Bitcoin, ticker: "BTC", logo: "", address: "")
    
    var amountInSats: Int64 {
        return Int64(amountDecimal * 100000000)
    }
    
    var feeInSats: Int64 {
        
        if gasDecimal == 0  {
            return Int64(20) // 20 sats is the default
        }
        
        return  Int64(gasDecimal * 100000000) // Normaly it comes int BTC
    }
    
    var amountDecimal: Double {
        let amountString = amount.replacingOccurrences(of: ",", with: ".")
        return Double(amountString) ?? 0
    }
    
    var gasDecimal: Double {
        let gasString = gas.replacingOccurrences(of: ",", with: ".")
        return Double(gasString) ?? 0
    }
    
    func parseCryptoURI(_ uri: String) {
        guard let url = URLComponents(string: uri) else {
            print("Invalid URI")
            return
        }
        
        // Use the path for the address if the host is nil, which can be the case for some URIs.
        toAddress = url.host ?? url.path
        
        url.queryItems?.forEach { item in
            switch item.name {
            case "amount":
                amount = item.value ?? ""
            case "label", "message":
                // For simplicity, appending label and message to memo, separated by spaces
                if let value = item.value, !value.isEmpty {
                    memo += (memo.isEmpty ? "" : " ") + value
                }
            default:
                print("Unknown query item: \(item.name)")
            }
        }
    }
    
    func toString() -> String {
        let fromAddressStr = "\(fromAddress)"
        let toAddressStr = "\(toAddress)"
        let amountStr = "\(amount)"
        let memoStr = "\(memo)"
        let gasStr = "\(gas)"

        return "fromAddress: \(fromAddressStr), toAddress: \(toAddressStr), amount: \(amountStr), memo: \(memoStr), gas: \(gasStr)"
    }
    
}
