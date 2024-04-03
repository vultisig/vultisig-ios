import SwiftUI
import Foundation
import BigInt
import OSLog

@MainActor
class EtherScanService {
    private let logger = Logger(subsystem: "etherscan-service", category: "service")
    static let shared = EtherScanService()
    private init() {}
    
    private var cacheSafeFeeGwei: [String: (data: Int64, timestamp: Date)] = [:]
    private var cacheOracle: [String: (data: (Int64, Int64), timestamp: Date)] = [:]
    private var cacheGasPrice: [String: (data: BigInt, timestamp: Date)] = [:]
    private var cacheNonce: [String: (data: Int64, timestamp: Date)] = [:]
    
    func getEthBalance(coin: Coin,fromAddress: String) async -> (rawBalance: String, priceRate:Double) {
        var rawBalance = "0"
        var cryptoPrice = 0.0
        do {
            // Start fetching all information concurrently
            cryptoPrice = CryptoPriceService.shared.cryptoPrices?.prices[coin.priceProviderId]?["usd"] ?? 0.0
            
            if !coin.isNativeToken {
                rawBalance = try await fetchTokenRawBalance(contractAddress: coin.contractAddress, address: fromAddress)
            } else {
                rawBalance = try await fetchEthRawBalance(address: fromAddress)
            }
            
        } catch let error as EtherScanError {
            handleEtherScanError(error)
        } catch {
            print(error.localizedDescription)
        }
        return (rawBalance,cryptoPrice)
    }
    
    func getETHGasInfo(fromAddress: String) async throws -> (gasPrice:String,priorityFee:Int64,nonce:Int64){
        async let (gasPrice, priorityFee) = fetchOracle()
        async let nonce = fetchNonce(address: fromAddress)
        return (String(try await gasPrice),try await priorityFee,try await nonce)
    }
    
    func broadcastTransaction(hex: String) async throws -> String {
        let data = try await Utils.asyncPostRequest(urlString: Endpoint.broadcastEtherscanTransaction(hex: hex), headers: [:], body: Data())
        guard let result = extractResult(fromData: data) else {
            throw EtherScanError.resultExtractionFailed
        }
        return result
    }
    
    func fetchTransactions(forAddress address: String) async throws -> ([EtherscanAPITransactionDetail], String) {
        let decodedResponse: EtherscanAPIResponse = try await Utils.fetchObject(from: Endpoint.fetchEtherscanTransactions(address: address))
        if let transactions = decodedResponse.result {
            return (transactions, address)
        } else {
            throw EtherScanError.decodingError("Error to decode the transaction")
        }
    }
    
    func fetchERC20Transactions(forAddress address: String, contractAddress: String) async throws -> ([EtherscanAPITransactionDetail], String) {
        let decodedResponse:EtherscanAPIResponse = try await Utils.fetchObject(from: Endpoint.fetchERC20Transactions(address: address, contractAddress: contractAddress))
        if let transactions = decodedResponse.result {
            return (transactions, address)
        } else {
            throw EtherScanError.decodingError("Error to decode the transaction")
        }
    }
    
    func estimateGasForERC20Transfer(toAddress: String ,contractAddress: String,amountInTokenWei: BigInt) async throws -> BigInt {
        let data = constructERC20TransferData(recipientAddress: toAddress, value: amountInTokenWei)
        let urlString = Endpoint.fetchEtherscanEstimateGasForERC20Transaction(data: data, contractAddress: contractAddress)
        let resultData = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        guard let resultString = extractResult(fromData: resultData) else {
            throw EtherScanError.jsonDecodingError
        }
        
        let trimmedResultString = resultString.trimmingCharacters(in: CharacterSet(charactersIn: "0x"))
        guard let intResult = BigInt(trimmedResultString, radix: 16) else {
            throw EtherScanError.conversionError
        }
        
        return intResult
    }
    
    func estimateGasForEthTransaction(senderAddress: String, recipientAddress: String, value: BigInt, memo: String?) async throws -> BigInt {
        let data = "0x" + (memo?.data(using: .utf8)?.map { String(format: "%02x", $0) }.joined() ?? "")
        let to = recipientAddress
        let valueHex = "0x" + String(value, radix: 16)
        let urlString = Endpoint.fetchEtherscanEstimateGasForEthTransaction(data: data, to: to, valueHex: valueHex)
        let resultData = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        
        guard let resultString = extractResult(fromData: resultData) else {
            throw EtherScanError.jsonDecodingError
        }
        
        let trimmedResultString = resultString.trimmingCharacters(in: CharacterSet(charactersIn: "0x"))
        guard let intResult = BigInt(trimmedResultString, radix: 16) else {
            throw EtherScanError.conversionError
        }
        
        return intResult
    }
    
    func fetchTokenRawBalance(contractAddress:String, address: String) async throws -> String {
        let urlString = Endpoint.fetchEtherscanTokenBalance(contractAddress: contractAddress, address: address)
        let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        if let resultString = extractResult(fromData: data) {
            return resultString
        } else {
            throw EtherScanError.conversionError
        }
    }
    
    func fetchEthRawBalance(address: String) async throws -> String {
        let urlString = Endpoint.fetchEtherscanBalance(address: address)
        let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        
        if let resultString = extractResult(fromData: data) {
            return resultString
        } else {
            throw EtherScanError.conversionError
        }
    }
    
    func fetchNonce(address: String) async throws -> Int64 {
        let cacheKey = "\(address)-etherscan-nonce"
        
        if let cachedData: Int64 = await Utils.getCachedData(cacheKey: cacheKey, cache: cacheNonce, timeInSeconds: 60) {
            return cachedData
        }
        
        let urlString = Endpoint.fetchEtherscanTransactionCount(address: address)
        let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        
        guard let resultString = extractResult(fromData: data) else {
            throw EtherScanError.jsonDecodingError
        }
        
        let trimmedResultString: String
        if resultString.hasPrefix("0x") {
            trimmedResultString = String(resultString.dropFirst(2))
        } else {
            trimmedResultString = resultString
        }
        
        guard let intResult = Int64(trimmedResultString, radix: 16) else {
            throw EtherScanError.conversionError
        }
        
        self.cacheNonce[cacheKey] = (data: intResult, timestamp: Date())
        
        return intResult
    }
    
    func fetchGasPrice() async throws -> BigInt {
        let cacheKey = "etherscan-gas-price"
        
        if let cachedData: BigInt = await Utils.getCachedData(cacheKey: cacheKey, cache: cacheGasPrice, timeInSeconds: 60 * 5) {
            return cachedData
        }
        
        let urlString = Endpoint.fetchEtherscanGasPrice()
        let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        if let resultString = extractResult(fromData: data) {
            let trimmedResultString = resultString.trimmingCharacters(in: CharacterSet(charactersIn: "0x"))
            if let bigIntResult = BigInt(trimmedResultString, radix: 16) {
                let bigIntResultGwei = bigIntResult / BigInt(1_000_000_000)
                self.cacheGasPrice[cacheKey] = (data: bigIntResultGwei, timestamp: Date())
                return bigIntResultGwei
            } else {
                throw EtherScanError.fetchGasPriceConversionError
            }
        } else {
            throw EtherScanError.fetchGasPriceConversionError
        }
    }
    
    func fetchOracle() async throws -> (Int64, Int64) {
        let cacheKey = "etherscan-gas-priority-fee-gwei"
        
        if let cachedData: (Int64, Int64) = await Utils.getCachedData(cacheKey: cacheKey, cache: cacheOracle, timeInSeconds: 60 * 5) {
            return cachedData
        }
        
        let urlString = Endpoint.fetchEtherscanGasOracle()
        let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        
        guard let resultSafeGasPrice = Utils.extractResultFromJson(fromData: data, path: "result.SafeGasPrice"),
              let resultSafeGasPriceString = resultSafeGasPrice as? String else {
            throw EtherScanError.customError("Error to convert the result Safe Gas Price to String")
        }
        
        guard let intResultSafeGasPrice = Int64(resultSafeGasPriceString) else {
            throw EtherScanError.customError("Error to convert the result Safe Gas Price String to Int64")
        }
        
        guard let resultProposeGasPrice = Utils.extractResultFromJson(fromData: data, path: "result.ProposeGasPrice"),
              let proposeGasPriceString = resultProposeGasPrice as? String,
              let proposeGasPriceInt = Int64(proposeGasPriceString) else {
            throw EtherScanError.customError("Error to extract the propose gas price and convert to Int64")
        }
        
        if proposeGasPriceInt == 0 {
            throw EtherScanError.fetchGasPriceConversionError
        }
        
        guard let resultSuggestBaseFee = Utils.extractResultFromJson(fromData: data, path: "result.suggestBaseFee"),
              let suggestBaseFeeString = resultSuggestBaseFee as? String,
              let suggestBaseFeeDouble = Double(suggestBaseFeeString) else {
            throw EtherScanError.customError("Error to extract the suggested base fee and convert to Double")
        }
        
        if suggestBaseFeeDouble == 0.0 {
            throw EtherScanError.customError("ERROR: Extract suggestBaseFee is ZERO")
        }
        
        var priorityFeeGweiDouble = Double(proposeGasPriceInt) - suggestBaseFeeDouble
        
        // It can't be ZERO, so we calculate it.
        if priorityFeeGweiDouble > 0.0, priorityFeeGweiDouble < 1 {
            priorityFeeGweiDouble = 1
        }
        
        if priorityFeeGweiDouble == 0 {
            throw EtherScanError.customError("ERROR: Calculate priorityFeeGwei by subtracting suggestBaseFee from ProposeGasPrice and round the result")
        }
        
        let priorityFeeGwei = Int64(round(priorityFeeGweiDouble))
        
        // Update cache and return priorityFeeGwei
        self.cacheOracle[cacheKey] = (data: (intResultSafeGasPrice, priorityFeeGwei), timestamp: Date())
        
        return (intResultSafeGasPrice, priorityFeeGwei)
    }
    
    private func extractResult(fromData data: Data) -> String? {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let result = json["result"] as? String {
                    return result
                } else if let error = json["error"] as? [String: Any], let message = error["message"] as? String, message == "already known" {
                    return "Your other device already broadcasted it"
                }
            }
        } catch {
            print("JSON decoding error: \(error)")
        }
        return nil
    }
    
    
    private func constructERC20TransferData(recipientAddress: String, value: BigInt) -> String {
        let methodId = "a9059cbb"
        let strippedRecipientAddress = recipientAddress.stripHexPrefix()
        let paddedAddress = strippedRecipientAddress.paddingLeft(toLength: 64, withPad: "0")
        let valueHex = String(value, radix: 16)
        let paddedValue = valueHex.paddingLeft(toLength: 64, withPad: "0")
        let data = "0x" + methodId + paddedAddress + paddedValue
        return data
    }
    
    enum EtherScanError: Error, CustomStringConvertible {
        case invalidURL
        case httpError(Int, String)
        case apiError(String)
        case unexpectedResponse
        case decodingError(String)
        case unknown(Error)
        case resultParsingError
        case conversionError
        case jsonDecodingError
        case resultExtractionFailed
        case customError(String)
        
        case fetchNonceConversionError
        case fetchGasPriceConversionError
        
        
        var description: String {
            switch self {
            case .invalidURL: return "invalidURL"
            case .httpError(let statusCode, let message): return "httpError(\(statusCode), \(message))"
            case .apiError(let message): return "apiError(\(message))"
            case .unexpectedResponse: return "unexpectedResponse"
            case .decodingError(let message): return "decodingError(\(message))"
            case .unknown(let error): return "unknown(\(error))"
            case .resultParsingError: return "resultParsingError"
            case .conversionError: return "conversionError"
            case .jsonDecodingError: return "jsonDecodingError"
            case .resultExtractionFailed: return "resultExtractionFailed"
            case .customError(let message): return "customError(\(message))"
                
            case .fetchNonceConversionError: return "fetchNonceConversionError"
            case .fetchGasPriceConversionError: return "fetchGasPriceConversionError"
            }
        }
    }
    
    private func handleEtherScanError(_ error: EtherScanError) {
        print(error.description)
    }
    
    static func convertToEther(fromWei value: String, _ decimals: Int = EVMHelper.ethDecimals) -> String {
        if let wei = Decimal(string: value) {
            let decimalValue = Decimal(pow(10.0, Double(decimals)))
            let ether = wei / decimalValue // Correctly perform exponentiation
            return "\(ether)"
        } else {
            return "Invalid Value"
        }
    }
    
    func calculateTransactionFee(gasUsed: String, gasPrice: String) -> String {
        guard let gasUsedDouble = Double(gasUsed), let gasPriceDouble = Double(gasPrice) else {
            return "Invalid Data"
        }
        
        let feeInWei = Decimal(gasUsedDouble * gasPriceDouble)
        let feeInEther = feeInWei / Decimal(EVMHelper.wei)
        let handler = NSDecimalNumberHandler(roundingMode: .plain, scale: 6, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)
        let roundedDecimal = NSDecimalNumber(decimal: feeInEther).rounding(accordingToBehavior: handler)
        return "\(roundedDecimal)"
    }
}
