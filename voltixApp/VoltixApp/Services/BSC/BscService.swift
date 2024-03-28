//
//  BscService.swift
//  VoltixApp
//
//  Created by Johnny Luo on 28/3/2024.
//

import SwiftUI
import Foundation
import BigInt
import OSLog

public class BSCService {
    private let logger = Logger(subsystem: "bsc", category: "service")
    static let shared = BSCService()
    private init() {}
    
    private var cacheSafeFeeGwei: [String: (data: Int64, timestamp: Date)] = [:]
    private var cacheOracle: [String: (data: (Int64, Int64), timestamp: Date)] = [:]
    private var cacheGasPrice: [String: (data: BigInt, timestamp: Date)] = [:]
    private var cacheNonce: [String: (data: Int64, timestamp: Date)] = [:]
    
    func getBNBBalance(tx: SendTransaction) async throws -> Void {
        
        // Start fetching all information concurrently
        async let cryptoPrice = CryptoPriceService.shared.cryptoPrices?.prices[tx.coin.priceProviderId]?["usd"]
        if let priceRateUsd = await cryptoPrice {
            tx.coin.priceRate = priceRateUsd
        }
        if !tx.coin.isNativeToken {
            tx.coin.rawBalance = try await fetchTokenRawBalance(contractAddress: tx.coin.contractAddress, address: tx.fromAddress)
        } else {
            tx.coin.rawBalance = try await fetchBNBRawBalance(address: tx.fromAddress)
        }
        
    }
    
    func getBscGasInfo(fromAddress: String) async throws -> (gasPrice:String,priorityFee:Int64,nonce:Int64){
        async let (gasPrice, priorityFee) = fetchOracle()
        async let nonce = fetchNonce(address: fromAddress)
        return (String(try await gasPrice),try await priorityFee,try await nonce)
    }
    
    func broadcastTransaction(hex: String) async throws -> String {
        let data = try await Utils.asyncPostRequest(urlString: Endpoint.broadcastBscTransaction(hex: hex), headers: [:], body: Data())
        
        guard let result = try extractResult(data: data) else {
            throw HelperError.runtimeError("Error to decode transaction broadcast result")
        }
        return result
    }
    
    func fetchTransactions(forAddress address: String) async throws -> ([EtherscanAPITransactionDetail], String) {
        let decodedResponse: EtherscanAPIResponse = try await Utils.fetchObject(from: Endpoint.fetchBscTransactions(address: address))
        if let transactions = decodedResponse.result {
            return (transactions, address)
        } else {
            throw HelperError.runtimeError("Error to decode the transaction")
        }
    }
    
    func fetchBEP20Transactions(forAddress address: String, contractAddress: String) async throws -> ([EtherscanAPITransactionDetail], String) {
        let decodedResponse:EtherscanAPIResponse = try await Utils.fetchObject(from: Endpoint.fetchBRC20Transactions(address: address, contractAddress: contractAddress))
        if let transactions = decodedResponse.result {
            return (transactions, address)
        } else {
            throw HelperError.runtimeError("Error to decode the transaction")
        }
    }
    
    func estimateGasForBEP20Transfer(tx: SendTransaction) async throws -> BigInt {
        let data = constructERC20TransferData(recipientAddress: tx.toAddress, value: tx.amountInTokenWei)
        let urlString = Endpoint.fetchEtherscanEstimateGasForERC20Transaction(data: data, contractAddress: tx.coin.contractAddress)
        let resultData = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        
        guard let resultString = try extractResult(data: resultData) else {
            throw HelperError.runtimeError("Error to gas for BRC20 transfer")
        }
        
        let trimmedResultString = resultString.trimmingCharacters(in: CharacterSet(charactersIn: "0x"))
        guard let intResult = BigInt(trimmedResultString, radix: 16) else {
            throw HelperError.runtimeError("Error to convert gas result to BigInt")
        }
        
        return intResult
    }
    
    func estimateGasForBNBTransaction(senderAddress: String, recipientAddress: String, value: BigInt, memo: String?) async throws -> BigInt {
        let data = "0x" + (memo?.data(using: .utf8)?.map { String(format: "%02x", $0) }.joined() ?? "")
        let to = recipientAddress
        let valueHex = "0x" + String(value, radix: 16)
        let urlString = Endpoint.fetchBscscanEstimateGasForBNBTransaction(data: data, to: to, valueHex: valueHex)
        let resultData = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        
        guard let resultString = try extractResult(data: resultData) else {
            throw HelperError.runtimeError("Error to gas for BNB transfer")
        }
        
        let trimmedResultString = resultString.trimmingCharacters(in: CharacterSet(charactersIn: "0x"))
        guard let intResult = BigInt(trimmedResultString, radix: 16) else {
            throw HelperError.runtimeError("Error to convert gas result to BigInt")
        }
        
        return intResult
    }
    
    func fetchTokenRawBalance(contractAddress:String, address: String) async throws -> String {
        let urlString = Endpoint.fetchBscTokenBalance(contractAddress: contractAddress, address: address)
        let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        if let resultString = Utils.extractResultFromJson(fromData: data, path: "result") as? String {
            return resultString
        }
        return ""
    }
    
    func fetchBNBRawBalance(address: String) async throws -> String {
        let urlString = Endpoint.fetchBscBalance(address: address)
        let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        if let resultString = Utils.extractResultFromJson(fromData: data, path: "result") as? String {
            return resultString
        } else {
            throw HelperError.runtimeError("fail to extract result from data")
        }
    }
    
    func fetchNonce(address: String) async throws -> Int64 {
        let cacheKey = "\(address)-bsc-nonce"
        
        if let cachedData: Int64 = try await Utils.getCachedData(cacheKey: cacheKey, cache: cacheNonce, timeInSeconds: 60) {
            return cachedData
        }
        
        let urlString = Endpoint.fetchBscTransactionCount(address: address)
        let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        
        guard let resultString = try extractResult(data: data) else {
            throw HelperError.runtimeError("fail to extract result from data")
        }
        
        let trimmedResultString: String
        if resultString.hasPrefix("0x") {
            trimmedResultString = String(resultString.dropFirst(2))
        } else {
            trimmedResultString = resultString
        }
        
        guard let intResult = Int64(trimmedResultString, radix: 16) else {
            throw HelperError.runtimeError("fail to convert string to int")
        }
        
        self.cacheNonce[cacheKey] = (data: intResult, timestamp: Date())
        
        return intResult
    }
    
    func fetchGasPrice() async throws -> BigInt {
        let cacheKey = "bsc-gas-price"
        
        if let cachedData: BigInt = try await Utils.getCachedData(cacheKey: cacheKey, cache: cacheGasPrice, timeInSeconds: 60 * 5) {
            return cachedData
        }
        
        let urlString = Endpoint.fetchBscGasPrice()
        let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        if let resultString = try extractResult(data: data) {
            let trimmedResultString = resultString.trimmingCharacters(in: CharacterSet(charactersIn: "0x"))
            if let bigIntResult = BigInt(trimmedResultString, radix: 16) {
                let bigIntResultGwei = bigIntResult / BigInt(1_000_000_000)
                self.cacheGasPrice[cacheKey] = (data: bigIntResultGwei, timestamp: Date())
                return bigIntResultGwei
            } else {
                throw HelperError.runtimeError("fail to convert string to int")
            }
        } else {
            throw HelperError.runtimeError("fail to convert string to int")
        }
    }
    
    func fetchOracle() async throws -> (Int64, Int64) {
        let cacheKey = "bsc-gas-priority-fee-gwei"
        
        if let cachedData: (Int64, Int64) = try await Utils.getCachedData(cacheKey: cacheKey, cache: cacheOracle, timeInSeconds: 60 * 5) {
            return cachedData
        }
        
        let urlString = Endpoint.fetchBscGasOracle()
        let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        
        guard let resultSafeGasPrice = Utils.extractResultFromJson(fromData: data, path: "result.SafeGasPrice"),
              let resultSafeGasPriceString = resultSafeGasPrice as? String else {
            throw HelperError.runtimeError("Error to convert the result Safe Gas Price to String")
        }
        
        guard let intResultSafeGasPrice = Int64(resultSafeGasPriceString) else {
            throw HelperError.runtimeError("Error to convert the result Safe Gas Price String to Int64")
        }
        
        guard let resultProposeGasPrice = Utils.extractResultFromJson(fromData: data, path: "result.ProposeGasPrice"),
              let proposeGasPriceString = resultProposeGasPrice as? String,
              let proposeGasPriceInt = Int64(proposeGasPriceString) else {
            throw HelperError.runtimeError("Error to extract the propose gas price and convert to Int64")
        }
        
        if proposeGasPriceInt == 0 {
            throw HelperError.runtimeError("Error to get the propose gas price from the oracle")
        }
        
        guard let resultSuggestBaseFee = Utils.extractResultFromJson(fromData: data, path: "result.suggestBaseFee"),
              let suggestBaseFeeString = resultSuggestBaseFee as? String,
              let suggestBaseFeeDouble = Double(suggestBaseFeeString) else {
            throw HelperError.runtimeError("Error to extract the suggested base fee and convert to Double")
        }
        
        if suggestBaseFeeDouble == 0.0 {
            throw HelperError.runtimeError("ERROR: Extract suggestBaseFee is ZERO")
        }
        
        var priorityFeeGweiDouble = Double(proposeGasPriceInt) - suggestBaseFeeDouble
        
        // It can't be ZERO, so we calculate it.
        if priorityFeeGweiDouble > 0.0, priorityFeeGweiDouble < 1 {
            priorityFeeGweiDouble = 1
        }
        
        if priorityFeeGweiDouble == 0 {
            throw HelperError.runtimeError("ERROR: Calculate priorityFeeGwei by subtracting suggestBaseFee from ProposeGasPrice and round the result")
        }
        
        let priorityFeeGwei = Int64(round(priorityFeeGweiDouble))
        
        // Update cache and return priorityFeeGwei
        self.cacheOracle[cacheKey] = (data: (intResultSafeGasPrice, priorityFeeGwei), timestamp: Date())
        
        return (intResultSafeGasPrice, priorityFeeGwei)
    }
    
   
    
    private func extractResult(data: Data) throws -> String? {
        logger.debug("Data: \(String(data: data, encoding: .utf8) ?? "nil")")
        let decoder = JSONDecoder()
        let result = try decoder.decode(JSONRPCResponse.self, from: data)
        if result.result != nil {
            return result.result
        }
        if result.error != nil {
            return result.error?.message
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
    
}
