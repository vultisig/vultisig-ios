import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers
import WalletCore
import BigInt
import Combine
import VultisigCommonData

class SendTransaction: ObservableObject, Hashable {

    @Published var fromAddress: String = ""
    @Published var toAddress: String = .empty
    @Published var amount: String = .empty
    @Published var amountInFiat: String = .empty
    @Published var memo: String = .empty
    @Published var gas: BigInt = .zero
    @Published var estematedGasLimit: BigInt?
    @Published var customGasLimit: BigInt?
    @Published var fee: BigInt = .zero
    @Published var feeMode: FeeMode = .normal
    @Published var sendMaxAmount: Bool = false
    @Published var isFastVault: Bool = false
    @Published var fastVaultPassword: String = .empty
    @Published var memoFunctionDictionary: ThreadSafeDictionary<String, String> = ThreadSafeDictionary()
    
    @Published var coin: Coin = .example
    @Published var transactionType: VSTransactionType = .unspecified

    var gasLimit: BigInt {
        return customGasLimit ?? estematedGasLimit ?? BigInt(EVMHelper.defaultETHTransferGasUnit)
    }

    var isAmountExceeded: Bool {
        if (sendMaxAmount && coin.chainType == .UTXO) || !coin.isNativeToken {
            let comparison = amountInRaw > coin.rawBalance.toBigInt(decimals: coin.decimals)
            return comparison
        }

        let totalTransactionCost = amountInRaw + gas
        let comparison = totalTransactionCost > coin.rawBalance.toBigInt(decimals: coin.decimals)
        return comparison
    }
    
    var isDeposit: Bool {
        !memoFunctionDictionary.allItems().isEmpty
    }
    
    var canBeReaped: Bool {
        if coin.ticker != Chain.polkadot.ticker {
            return false
        }
        
        let totalBalance = BigInt(coin.rawBalance) ?? BigInt.zero
        let totalTransactionCost = amountInRaw + gas
        let remainingBalance = totalBalance - totalTransactionCost
        
        return remainingBalance < PolkadotHelper.defaultExistentialDeposit
    }
    
    func hasEnoughNativeTokensToPayTheFees(specific: BlockChainSpecific) async -> (Bool, String) {
        var errorMessage = ""
        guard !coin.isNativeToken else { return (true, errorMessage) }
        
        if let vault = ApplicationState.shared.currentVault {
            if let nativeToken = vault.coins.nativeCoin(chain: coin.chain) {
                await BalanceService.shared.updateBalance(for: nativeToken)
                
                let nativeTokenBalance = nativeToken.rawBalance.toBigInt()
                
                if specific.fee > nativeTokenBalance {
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
            if let nativeToken = vault.coins.nativeCoin(chain: coin.chain) {
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
        return Decimal(gas)
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
                if let nativeToken = vault.coins.nativeCoin(chain: coin.chain) {
                    decimals = nativeToken.decimals
                }
            }
        }
        
        return "\((gasDecimal / pow(10,decimals)).formatToDecimal(digits: decimals).description) \(coin.chain.feeUnit)"
    }

    init() { }

    init(coin: Coin) {
        self.reset(coin: coin)
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
        self.gas = .zero
        self.estematedGasLimit = nil
        self.customGasLimit = nil
        self.feeMode = .normal
        self.coin = coin
        self.sendMaxAmount = false
        self.fromAddress = coin.address
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
