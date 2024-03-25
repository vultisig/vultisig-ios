import Foundation
import CodeScanner
import OSLog
import SwiftUI
import UniformTypeIdentifiers
import WalletCore
import BigInt

class SendTransaction: ObservableObject, Hashable {
    @Published var toAddress: String = ""
    @Published var amount: String = ""
    @Published var amountInUSD: String = ""
    @Published var memo: String = ""
    @Published var gas: String = ""
    @Published var nonce: Int64 = 0
	@Published var coin: Coin = Coin(
		chain: Chain.Bitcoin,
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
		isNativeToken: false,
        feeDefault: "20"
	)

    var fromAddress: String {
        coin.address
    }
    
    var amountInWei: BigInt {
        BigInt(amountDecimal * pow(10, 18))
    }
    
    var amountInGwei: Int64 {
        Int64(amountDecimal * pow(10, 9))
    }
    
    var totalEthTransactionCostWei: BigInt {
        amountInWei + feeInWei
    }
	
	var amountInTokenWeiInt64: Int64 {
		let decimals = Double(coin.decimals ?? "18") ?? 18.0 // The default is always in WEI unless the token has a different one like UDSC
		
		return Int64(amountDecimal * pow(10, decimals))
	}
    
    var amountInTokenWei: BigInt {
        let decimals = Double(coin.decimals ?? "18") ?? 18.0 // The default is always in WEI unless the token has a different one like UDSC
        
        return BigInt(amountDecimal * pow(10, decimals))
    }
    
    // The fee comes in GWEI
    var feeInWei: BigInt {
        let gasString: String = gas
        
        if let gasGwei = BigInt(gasString) {
            let gasWei: BigInt = gasGwei * 1_000_000_000 // Equivalent to 10^9
            return gasWei
        } else {
            print("Invalid gas value")
        }
        
        return 0
    }
    
	var amountInLamports: Int64 {
		Int64(amountDecimal * 1_000_000_000)
	}
	
    var amountInSats: Int64 {
        Int64(amountDecimal * 100_000_000)
    }
    
    var feeInSats: Int64 {
        Int64(gas) ?? Int64(20) // Assuming that the gas is in sats
    }
    
    var amountDecimal: Double {
        let amountString = amount.replacingOccurrences(of: ",", with: ".")
        return Double(amountString) ?? 0
    }
    
    var gasDecimal: Double {
        let gasString = gas.replacingOccurrences(of: ",", with: ".")
        return Double(gasString) ?? 0
    }
    
    var gasFeePredictionForEvm: Double {
        if let gasDouble = Double(gas), let feeDefaultDouble = Double(coin.feeDefault) {
            return calculateTransactionFee(gasPriceGwei: gasDouble, gasUsed: feeDefaultDouble)
        } else {
            return 0.0
        }
    }
    
    var gasFeePredictionForEvmUsd: Double {
        if let gasDouble = Double(gas), let feeDefaultDouble = Double(coin.feeDefault) {
            let feeInEth = calculateTransactionFee(gasPriceGwei: gasDouble, gasUsed: feeDefaultDouble)
            return feeInEth * coin.priceRate
        } else {
            return 0.0
        }
    }

    private func calculateTransactionFee(gasPriceGwei: Double, gasUsed: Double) -> Double {
        let gweiToEthConversionFactor = 1_000_000_000.0
        let transactionFeeGwei = gasPriceGwei * gasUsed
        let transactionFeeEth = transactionFeeGwei / gweiToEthConversionFactor
        return transactionFeeEth
    }

    init() {
        self.toAddress = ""
        self.amount = ""
        self.memo = ""
        self.gas = ""
    }
	
	init(coin: Coin) {
		self.toAddress = ""
		self.amount = ""
		self.memo = ""
		self.gas = ""
		self.coin = coin
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
