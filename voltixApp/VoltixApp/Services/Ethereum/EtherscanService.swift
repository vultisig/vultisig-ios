import SwiftUI
import Foundation
import BigInt
import OSLog

@MainActor
public class EtherScanService: ObservableObject {
    private let logger = Logger(subsystem: "etherscan-service", category: "service")
    static let shared = EtherScanService()
    private init() {}
    
    private var cacheSafeFeeGwei: [String: (data: Int64, timestamp: Date)] = [:]
    private var cachePriorityFeeGwei: [String: (data: Int64, timestamp: Date)] = [:]
    private var cacheGasPrice: [String: (data: BigInt, timestamp: Date)] = [:]
    private var cacheNonce: [String: (data: Int64, timestamp: Date)] = [:]
    
    func getEthInfo(tx: SendTransaction) async throws -> Void {
        
        do {
            // Start fetching all information concurrently
            async let gasPrice = fetchSafeFeeGwei()
            async let nonce = fetchNonce(address: tx.fromAddress)
            async let cryptoPrice = CryptoPriceService.shared.cryptoPrices?.prices[tx.coin.priceProviderId]?["usd"]
            
            if let priceRateUsd = await cryptoPrice {
                tx.coin.priceRate = priceRateUsd
            }
            if !tx.coin.isNativeToken {
                tx.coin.rawBalance = try await fetchTokenRawBalance(contractAddress: tx.coin.contractAddress, address: tx.fromAddress)
            } else {
                tx.coin.rawBalance = try await fetchEthRawBalance(address: tx.fromAddress)
            }
            
            tx.gas = String(try await gasPrice)
            tx.nonce = try await nonce
        } catch let error as EtherScanError {
            handleEtherScanError(error)
        } catch {
            print(error.localizedDescription)
        }
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
    
    func estimateGasForERC20Transfer(tx: SendTransaction) async throws -> BigInt {
        let data = constructERC20TransferData(recipientAddress: tx.toAddress, value: tx.amountInTokenWei)
        let urlString = Endpoint.fetchEtherscanEstimateGasForERC20Transaction(data: data, contractAddress: tx.coin.contractAddress)
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
        
        do {
            if let cachedData: Int64 = try await Utils.getCachedData(cacheKey: cacheKey, cache: cacheNonce, timeInSeconds: 60) {
                return cachedData
            }
        } catch {
            throw error
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
        
        do {
            if let cachedData: BigInt = try await Utils.getCachedData(cacheKey: cacheKey, cache: cacheGasPrice, timeInSeconds: 60 * 5) {
                return cachedData
            }
        } catch {
            throw error
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
    
    func fetchSafeFeeGwei() async throws -> Int64 {
        let cacheKey = "etherscan-gas-proposed-fee-gwei"
        
        do {
            if let cachedData: Int64 = try await Utils.getCachedData(cacheKey: cacheKey, cache: cacheSafeFeeGwei, timeInSeconds: 60 * 5) {
                return cachedData
            }
        } catch {
            throw error
        }
        
        let urlString = Endpoint.fetchEtherscanGasOracle()
        let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        
        // Extract ProposeGasPrice
        guard let resultProposeGasPrice = Utils.extractResultFromJson(fromData: data, path: "result.SafeGasPrice"),
              let resultProposeGasPriceString = resultProposeGasPrice as? String else {
            throw EtherScanError.fetchGasPriceConversionError
        }
        let trimmedResultStringProposeGasPrice = resultProposeGasPriceString.trimmingCharacters(in: CharacterSet(charactersIn: "0x"))
        
        guard let intResultProposeGasPrice = Int64(trimmedResultStringProposeGasPrice) else {
            throw EtherScanError.fetchGasPriceConversionError
        }
        
        self.cacheSafeFeeGwei[cacheKey] = (data: intResultProposeGasPrice, timestamp: Date())
        
        return intResultProposeGasPrice
    }
    
    func fetchPriorityFeeGwei() async throws -> Int64 {
        let cacheKey = "etherscan-gas-priority-fee-gwei"
        
        do {
            if let cachedData: Int64 = try await Utils.getCachedData(cacheKey: cacheKey, cache: cachePriorityFeeGwei, timeInSeconds: 60 * 5) {
                return cachedData
            }
        } catch {
            throw error
        }
        
        let urlString = Endpoint.fetchEtherscanGasOracle()
        let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        
        // Extract ProposeGasPrice
        guard let resultProposeGasPrice = Utils.extractResultFromJson(fromData: data, path: "result.ProposeGasPrice"),
              let resultProposeGasPriceString = resultProposeGasPrice as? String else {
            throw EtherScanError.fetchGasPriceConversionError
        }
        let trimmedResultStringProposeGasPrice = resultProposeGasPriceString.trimmingCharacters(in: CharacterSet(charactersIn: "0x"))
        
        guard let bigIntResultProposeGasPrice = Int64(trimmedResultStringProposeGasPrice) else {
            throw EtherScanError.fetchGasPriceConversionError
        }
        
        // Extract suggestBaseFee
        guard let resultSuggestBaseFee = Utils.extractResultFromJson(fromData: data, path: "result.suggestBaseFee"),
              let resultSuggestBaseFeeString = resultSuggestBaseFee as? String else {
            throw EtherScanError.fetchGasPriceConversionError
        }
        let trimmedResultStringSuggestBaseFee = resultSuggestBaseFeeString.trimmingCharacters(in: CharacterSet(charactersIn: "0x"))
        
        guard let bigIntResultSuggestBaseFee = Int64(trimmedResultStringSuggestBaseFee) else {
            throw EtherScanError.fetchGasPriceConversionError
        }
        
        // Calculate priorityFeeGwei
        let priorityFeeGwei = bigIntResultProposeGasPrice - bigIntResultSuggestBaseFee
        
        // Update cache and return priorityFeeGwei
        self.cachePriorityFeeGwei[cacheKey] = (data: priorityFeeGwei, timestamp: Date())
        
        return priorityFeeGwei
    }
    
    private func extractResult(fromData data: Data) -> String? {
        do {
            logger.debug("Data: \(String(data: data, encoding: .utf8) ?? "nil")")
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? String {
                return result
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
}
