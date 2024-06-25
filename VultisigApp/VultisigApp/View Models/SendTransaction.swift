import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers
import WalletCore
import BigInt
import Combine

#if os(iOS)
import CodeScanner
#endif

class SendTransaction: ObservableObject, Hashable {
    @Published var toAddress: String = .empty
    @Published var amount: String = .empty
    @Published var amountInFiat: String = .empty
    @Published var memo: String = .empty
    @Published var gas: String = .empty
    @Published var sendMaxAmount: Bool = false
    @Published var memoFunctionDictionary: ThreadSafeDictionary<String, String> = ThreadSafeDictionary()

    @Published var coin: Coin = .example

    private var _fromAddress: String = ""

    var fromAddress: String {
        return _fromAddress
    }
    
    var isAmountExceeded: Bool {
        
        if (sendMaxAmount && coin.chainType == .UTXO) || !coin.isNativeToken {
            let comparison = amountInRaw > coin.rawBalance.toBigInt(decimals: coin.decimals)
            return comparison
        }
        
        let gasBigInt = gas.toBigInt()
        let totalTransactionCost = amountInRaw + gasBigInt
        let comparison = totalTransactionCost > coin.rawBalance.toBigInt(decimals: coin.decimals)
        return comparison
    }
    
    
    var canBeReaped: Bool {
        if coin.ticker != Chain.polkadot.ticker {
            return false
        }
        
        let totalBalance = BigInt(coin.rawBalance) ?? BigInt.zero
        let gasInt = BigInt(gas) ?? BigInt.zero
        let totalTransactionCost = amountInRaw + gasInt
        let remainingBalance = totalBalance - totalTransactionCost
        
        return remainingBalance < PolkadotHelper.defaultExistentialDeposit
    }
    
    func hasEnoughNativeTokensToPayTheFees(specific: BlockChainSpecific) async -> (Bool, String) {
        var errorMessage = ""
        guard !coin.isNativeToken else { return (true, errorMessage) }
        
        let totalFeeWei = coin.feeDefault.toBigInt() * specific.gas
        if let vault = ApplicationState.shared.currentVault {
            if let nativeToken = vault.coins.first(where: { $0.isNativeToken && $0.chain.name == coin.chain.name }) {
                await BalanceService.shared.updateBalance(for: nativeToken)
                
                let nativeTokenBalance = nativeToken.rawBalance.toBigInt()
                
                if totalFeeWei > nativeTokenBalance {
                    errorMessage = "Insufficient \(nativeToken.ticker) balance for the \(coin.ticker) transaction fees."
                    
                    return (false, errorMessage)
                }
                return (true, errorMessage)
            } else {
                errorMessage = "No native token found for chain \(coin.chain.name)"
                return (false, errorMessage)
            }
        }
        return (false, errorMessage)
    }
    
    
    func getNativeTokenBalance() async -> String {
        guard !coin.isNativeToken else { return .zero }
        
        if let vault = ApplicationState.shared.currentVault {
            if let nativeToken = vault.coins.first(where: { $0.isNativeToken && $0.chain.name == coin.chain.name }) {
                await BalanceService.shared.updateBalance(for: nativeToken)
                let nativeTokenRawBalance = Decimal(string: nativeToken.rawBalance) ?? .zero
                
                let nativeDecimals = nativeToken.decimals
                
                let nativeTokenBalance = nativeTokenRawBalance / pow(10, nativeDecimals)
                
                let nativeTokenBalanceDecimal = nativeTokenBalance.description.formatToDecimal(digits: 8)
                
                return "\(nativeTokenBalanceDecimal) \(nativeToken.ticker)"
            } else {
                print("No native token found for chain \(coin.chain.name)")
                return .zero
            }
        }
        print("Failed to access current vault")
        return .zero
    }
    
    var amountInRaw: BigInt {
        let decimals = coin.decimals
        let amountInDecimals = amountDecimal * pow(10, decimals)
        return amountInDecimals.description.toBigInt(decimals: decimals)
    }
    
    var amountDecimal: Decimal {
        let decimalValue = amount.toDecimal()
        let truncatedDecimal = decimalValue.truncated(toPlaces: coin.decimals)
        return truncatedDecimal
    }
    
    var gasDecimal: Decimal {
        let gasString = gas.replacingOccurrences(of: ",", with: ".")
        return Decimal(string:gasString) ?? 0
    }
    
    var gasInReadable: String {
        var decimals = coin.decimals
        if coin.chain.chainType == .EVM {
            // convert to Gwei , show as Gwei for EVM chain only
            guard let weiPerGWeiDecimal = Decimal(string: EVMHelper.weiPerGWei.description) else {
                return .empty
            }
            return "\(gasDecimal / weiPerGWeiDecimal) \(coin.chain.feeUnit)"
        }
        
        // If not a native token we need to get the decimals from the native token
        if !coin.isNativeToken {
            if let vault = ApplicationState.shared.currentVault {
                if let nativeToken = vault.coins.first(where: { $0.isNativeToken && $0.chain.name == coin.chain.name }) {
                    decimals = nativeToken.decimals
                }
            }
        }
        
        return "\((gasDecimal / pow(10,decimals)).formatToDecimal(digits: decimals).description) \(coin.chain.feeUnit)"
    }
    
    init() {
        self.toAddress = .empty
        self.amount = .empty
        self.amountInFiat = .empty
        self.memo = .empty
        self.gas = .empty
        self.sendMaxAmount = false
    }
    
    init(coin: Coin) {
        self.reset(coin: coin)
    }
    
    init(toAddress: String, amount: String, memo: String, gas: String) {
        self.toAddress = toAddress
        self.amount = amount
        self.memo = memo
        self.gas = gas
        self.sendMaxAmount = false
    }
    
    init(toAddress: String, amount: String, memo: String, gas: String, coin: Coin) {
        self.toAddress = toAddress
        self.amount = amount
        self.memo = memo
        self.gas = gas
        self.coin = coin
        self.sendMaxAmount = false
        self._fromAddress = coin.address
    }
    
    static func == (lhs: SendTransaction, rhs: SendTransaction) -> Bool {
        lhs.fromAddress == rhs.fromAddress &&
        lhs.toAddress == rhs.toAddress &&
        lhs.amount == rhs.amount &&
        lhs.memo == rhs.memo &&
        lhs.gas == rhs.gas &&
        lhs.sendMaxAmount == rhs.sendMaxAmount
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(fromAddress)
        hasher.combine(toAddress)
        hasher.combine(amount)
        hasher.combine(memo)
        hasher.combine(gas)
        hasher.combine(sendMaxAmount)
    }
    
    func reset(coin: Coin) {
        self.toAddress = .empty
        self.amount = .empty
        self.amountInFiat = .empty
        self.memo = .empty
        self.gas = .empty
        self.coin = coin
        self.sendMaxAmount = false
        self._fromAddress = coin.address
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
}
