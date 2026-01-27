import Foundation
import OSLog
import SwiftUI
import VultisigCommonData

import UniformTypeIdentifiers
import WalletCore
import BigInt
class SendTransaction: ObservableObject, Hashable {
    @Published var fromAddress: String = ""
    @Published var toAddress: String = .empty
    @Published var amount: String = .empty
    @Published var amountInFiat: String = .empty
    @Published var memo: String = .empty
    @Published var gas: BigInt = .zero
    @Published var estematedGasLimit: BigInt?
    @Published var customGasLimit: BigInt?
    @Published var customByteFee: BigInt?
    @Published var fee: BigInt = .zero
    @Published var isCalculatingFee: Bool = false
    @Published var feeMode: FeeMode = .default
    @Published var sendMaxAmount: Bool = false
    @Published var isFastVault: Bool = false
    @Published var fastVaultPassword: String = .empty
    @Published var isStakingOperation: Bool = false
    @Published var memoFunctionDictionary: ThreadSafeDictionary<String, String> = ThreadSafeDictionary()
    var wasmContractPayload: WasmExecuteContractPayload?

    @Published var coin: Coin = .example
    @Published var transactionType: VSTransactionType = .unspecified
    @Published var vault: Vault?

    var txVault: Vault? { vault ?? AppViewModel.shared.selectedVault }

    var gasLimit: BigInt {
        return customGasLimit ?? estematedGasLimit ?? BigInt(EVMHelper.defaultETHTransferGasUnit)
    }

    var byteFee: BigInt {
        return customByteFee ?? gas
    }

    var isAmountExceeded: Bool {
        // TRON staking operations: skip validation entirely
        // The balance is already validated in TronFreezeView/TronUnfreezeView
        let isTronStaking = coin.chain == .tron && isStakingOperation
        
        if isTronStaking {
            return false
        }
        
        if (sendMaxAmount && (coin.chainType == .UTXO || coin.chainType == .Cardano || coin.chainType == .Ton)) || !coin.isNativeToken {
            let comparison = amountInRaw > coin.rawBalance.toBigInt(decimals: coin.decimals)
            return comparison
        }

        // For UTXO and Cardano chains, use the actual fee (plan.fee) not the gas (sats/byte rate)
        let feeToUse = (coin.chainType == .UTXO || coin.chainType == .Cardano) ? fee : gas
        let totalTransactionCost = amountInRaw + feeToUse
        let comparison = totalTransactionCost > coin.rawBalance.toBigInt(decimals: coin.decimals)

        return comparison
    }

    var isDeposit: Bool {
        !memoFunctionDictionary.allItems().isEmpty && ![ChainType.UTXO, ChainType.Ripple, ChainType.Solana].contains(coin.chainType)
    }

    var canBeReaped: Bool {

        let tickers = [Chain.polkadot.ticker, Chain.ripple.ticker]
        if !tickers.contains(coin.ticker) {
            return false
        }

        let totalBalance = BigInt(coin.rawBalance) ?? BigInt.zero
        let totalTransactionCost = amountInRaw + gas
        let remainingBalance = totalBalance - totalTransactionCost

        switch coin.chainType {
        case .Polkadot:
            return remainingBalance < PolkadotHelper.defaultExistentialDeposit
        case .Ripple:
            return remainingBalance < RippleHelper.defaultExistentialDeposit
        default:
            return false
        }
    }

    func hasEnoughNativeTokensToPayTheFees(specific: BlockChainSpecific) async -> (Bool, String) {
        var errorMessage = ""
        guard !coin.isNativeToken else { return (true, errorMessage) }

        if let vault = txVault {
            if let nativeToken = vault.coins.nativeCoin(chain: coin.chain) {
                await BalanceService.shared.updateBalance(for: nativeToken)

                let nativeTokenBalance = nativeToken.rawBalance.toBigInt()

                if specific.fee > nativeTokenBalance {
                    errorMessage = String(format: "insufficientGasTokenError".localized, nativeToken.ticker, coin.ticker)

                    return (false, errorMessage)
                }
                return (true, errorMessage)
            } else {
                errorMessage = String(format: "noGasTokenFoundError".localized, coin.chain.name)
                return (false, errorMessage)
            }
        }
        errorMessage = "unableToVerifyGasTokenError".localized
        return (false, errorMessage)
    }

    func getNativeTokenBalance() async -> String {
        guard !coin.isNativeToken else { return .zero }

        if let vault = txVault {
            if let nativeToken = vault.coins.nativeCoin(chain: coin.chain) {
                await BalanceService.shared.updateBalance(for: nativeToken)
                let nativeTokenRawBalance = Decimal(string: nativeToken.rawBalance) ?? .zero

                let nativeDecimals = nativeToken.decimals

                let nativeTokenBalance = nativeTokenRawBalance / pow(10, nativeDecimals)

                let nativeTokenBalanceDecimal = nativeTokenBalance.formatForDisplay(maxDecimals: 8)

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
        // Get native coin for proper fee display (fees are always in native token)
        var nativeCoin = coin
        var decimals = coin.decimals

        if !coin.isNativeToken {
            if let vault = txVault {
                if let nativeToken = vault.coins.nativeCoin(chain: coin.chain) {
                    nativeCoin = nativeToken
                    decimals = nativeToken.decimals
                }
            }
        }

        if coin.chain.chainType == .EVM {
            // convert to Gwei , show as Gwei for EVM chain only
            guard let weiPerGWeiDecimal = Decimal(string: EVMHelper.weiPerGWei.description) else {
                return .empty
            }
            return "\(gasDecimal / weiPerGWeiDecimal) \(coin.chain.feeUnit)"
        }

        // For UTXO and Cardano chains, use total fee amount (like Android) instead of sats/byte rate
        let feeToDisplay = (coin.chainType == .UTXO || coin.chainType == .Cardano) ? fee : gas
        let feeDecimal = Decimal(feeToDisplay)

        return "\((feeDecimal / pow(10, decimals)).formatToDecimal(digits: decimals).description) \(nativeCoin.ticker)"
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
        self.fee = .zero  // Clear previous fee
        self.isCalculatingFee = false  // Reset UI state
        self.estematedGasLimit = nil
        self.customGasLimit = nil
        self.customByteFee = nil
        self.feeMode = .default
        self.coin = coin
        self.sendMaxAmount = false
        self.fromAddress = coin.address
        self.wasmContractPayload = nil  // Clear contract payload
        self.transactionType = .unspecified  // Reset transaction type
        self.memoFunctionDictionary = ThreadSafeDictionary()  // Clear memo functions
        self.fastVaultPassword = .empty  // Clear password state
        self.isStakingOperation = false // Reset staking operation flag
    }

    func parseCryptoURI(_ uri: String) {
        guard URLComponents(string: uri) != nil else {
            print("Invalid URI")
            return
        }

        let (address, amount, message) = Utils.parseCryptoURI(uri)

        self.toAddress = address
        self.amount = amount
        self.memo = message
    }
}
