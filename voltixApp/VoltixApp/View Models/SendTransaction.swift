import Foundation
import CodeScanner
import OSLog
import SwiftUI
import UniformTypeIdentifiers
import WalletCore
import BigInt

class SendTransaction: ObservableObject, Hashable {
    @Published var toAddress: String = .empty
    @Published var amount: String = .empty
    @Published var amountInFiat: String = .empty
    @Published var memo: String = .empty
    @Published var gas: String = .empty
    @Published var nonce: Int64 = 0
    var priorityFeeWei: Int64 = 0
    
    @Published var coin: Coin = Coin(
        chain: Chain.bitcoin,
        ticker: "BTC",
        logo: "",
        address: "",
        priceRate: 0.0,
        chainType: ChainType.UTXO,
        decimals: "8",
        hexPublicKey: "",
        feeUnit: "",
        priceProviderId: "",
        contractAddress: "",
        rawBalance: "0",
        isNativeToken: true,
        feeDefault: "20"
    )
    
    var fromAddress: String {
        coin.address
    }
    
    var amountInWei: BigInt {
        BigInt(amountDecimal * pow(10, Double(EVMHelper.ethDecimals)))
    }
                
    var amountInTokenWei: BigInt {
        let decimals = Double(coin.decimals) ?? Double(EVMHelper.ethDecimals) // The default is always in WEI unless the token has a different one like UDSC
        
        return BigInt(amountDecimal * pow(10, decimals))
    }
    
    var amountInLamports: BigInt {
        BigInt(amountDecimal * 1_000_000_000)
    }
    
    var amountInSats: BigInt {
        BigInt(amountDecimal * 100_000_000)
    }
    
    var feeInSats: Int64 {
        Int64(gas) ?? Int64(20) // Assuming that the gas is in sats
    }
    
    var amountDecimal: Double {
        let amountString = amount.replacingOccurrences(of: ",", with: ".")
        return Double(amountString) ?? 0
    }
    var amountInCoinDecimal: BigInt {
        let amountDouble = amountDecimal
        let decimals = Int(coin.decimals) ?? 8
        return BigInt(amountDouble * pow(10,Double(decimals)))
    }
    var gasDecimal: Decimal {
        let gasString = gas.replacingOccurrences(of: ",", with: ".")
        return Decimal(string:gasString) ?? 0
    }
    
    var gasInReadable: String {
        guard let decimals = Int(coin.decimals) else {
            return .empty
        }
        if coin.chain.chainType == .EVM {
            // convert to Gwei , show as Gwei for EVM chain only
            guard let weiPerGWeiDecimal = Decimal(string: EVMHelper.weiPerGWei.description) else {
                return .empty
            }
            return "\(gasDecimal / weiPerGWeiDecimal) \(coin.feeUnit)"
        }
        return "\((gasDecimal / pow(10,decimals)).formatToDecimal(digits: decimals).description) \(coin.feeUnit)"
    }
    
    init() {
        self.toAddress = .empty
        self.amount = .empty
        self.memo = .empty
        self.gas = .empty
    }
    
    init(coin: Coin) {
        self.reset(coin: coin)
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
        lhs.fromAddress == rhs.fromAddress &&
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
    
    func reset(coin: Coin) {
        self.toAddress = .empty
        self.amount = .empty
        self.memo = .empty
        self.gas = .empty
        self.coin = coin
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
        let properties = [
            "toAddress: \(toAddress)",
            "amount: \(amount)",
            "amountInFiat: \(amountInFiat)",
            "memo: \(memo)",
            "gas: \(gas)",
            "nonce: \(nonce)",
            "priorityFeeWei: \(priorityFeeWei)",
            "coin: \(coin.toString())",
            "fromAddress: \(fromAddress)",
            "amountInWei: \(amountInWei)",
            "amountInTokenWei: \(amountInTokenWei)",
            "amountInLamports: \(amountInLamports)",
            "amountInSats: \(amountInSats)",
            "feeInSats: \(feeInSats)",
            "amountDecimal: \(amountDecimal)",
            "amountInCoinDecimal: \(amountInCoinDecimal)",
            "gasDecimal: \(gasDecimal)"
        ]
        return properties.joined(separator: ",\n")
    }
}
