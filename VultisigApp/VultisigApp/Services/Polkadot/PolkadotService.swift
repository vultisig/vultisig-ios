//
//  PolkadotService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 28/04/24.
//

import Foundation
import BigInt

class PolkadotService: RpcService {
    static let rpcEndpoint = Endpoint.polkadotServiceRpc
    static let shared = PolkadotService(rpcEndpoint)

    private var cachePolkadotBalance: ThreadSafeDictionary<String, (data: BigInt, timestamp: Date)> = ThreadSafeDictionary()
    private var cachePolkadotGenesisBlockHash: ThreadSafeDictionary<String, (data: String, timestamp: Date)> = ThreadSafeDictionary()
        
    private func fetchBalance(address: String) async throws -> BigInt {
        let cacheKey = "polkadot-\(address)-balance"
        if let cachedData: BigInt = await Utils.getCachedData(cacheKey: cacheKey, cache: cachePolkadotBalance, timeInSeconds: 60*1) {
            return cachedData
        }
        
        let body = ["key": address]
        let maxRetries = 3
        let retryDelay: UInt64 = 1_000_000_000 // 1 second in nanoseconds

        for attempt in 1...maxRetries {
            do {
                let requestBody = try JSONEncoder().encode(body)
                let responseBodyData = try await Utils.asyncPostRequest(urlString: Endpoint.polkadotServiceBalance, headers: [:], body: requestBody)
                
                if let balance = Utils.extractResultFromJson(fromData: responseBodyData, path: "data.account.balance") as? String {
                    let decimalBalance = (Decimal(string: balance) ?? Decimal.zero) * pow(10, 10)
                    let bigIntResult = decimalBalance.description.toBigInt()
                    self.cachePolkadotBalance.set(cacheKey, (data: bigIntResult, timestamp: Date()))
                    return bigIntResult
                }
            } catch {
                print("PolkadotService > fetchBalance > Error encoding JSON: \(error), Attempt: \(attempt) of \(maxRetries)")
                if attempt < maxRetries {
                    try await Task.sleep(nanoseconds: retryDelay)
                } else {
                    return BigInt.zero
                }
            }
        }
        return BigInt.zero
    }

    private func fetchNonce(address: String) async throws -> BigInt {
        return try await intRpcCall(method: "system_accountNextIndex", params: [address])
    }
    
    private func fetchBlockHash() async throws -> String {
        return try await strRpcCall(method: "chain_getBlockHash", params: [])
    }
    
    private func fetchGenesisBlockHash() async throws -> String {
        let cacheKey = "polkadot-chain_getBlockHash-genesis"
        if let cachedData: String = await Utils.getCachedData(cacheKey: cacheKey, cache: cachePolkadotGenesisBlockHash, timeInSeconds: 60*60*24) {
            return cachedData
        }
        
        let genesis = try await strRpcCall(method: "chain_getBlockHash", params: [0])
        self.cachePolkadotGenesisBlockHash.set(cacheKey, (data: genesis, timestamp: Date()))
        return genesis
    }
    
    private func fetchRuntimeVersion() async throws -> (specVersion: UInt32, transactionVersion: UInt32) {
        return try await sendRPCRequest(method: "state_getRuntimeVersion", params: []) { result in
            guard let resultDict = result as? [String: Any] else {
                throw RpcServiceError.rpcError(code: 500, message: "Error to convert the RPC result to Dictionary")
            }
            
            guard let specVersion = resultDict["specVersion"] as? UInt32 else {
                throw RpcServiceError.rpcError(code: 404, message: "specVersion not found in the response")
            }
            
            guard let transactionVersion = resultDict["transactionVersion"] as? UInt32 else {
                throw RpcServiceError.rpcError(code: 404, message: "transactionVersion not found in the response")
            }
            
            return (specVersion, transactionVersion)
        }
    }
    
    private func fetchBlockHeader() async throws -> BigInt {
        return try await sendRPCRequest(method: "chain_getHeader", params: []) { result in
            guard let resultDict = result as? [String: Any] else {
                throw RpcServiceError.rpcError(code: 500, message: "Error to convert the RPC result to Dictionary")
            }
            
            guard let numberString = resultDict["number"] as? String else {
                throw RpcServiceError.rpcError(code: 404, message: "Block number not found in the response")
            }
            
            guard let bigIntNumber = BigInt(numberString.stripHexPrefix(), radix: 16) else {
                throw RpcServiceError.rpcError(code: 500, message: "Error to convert block number to BigInt")
            }
            return bigIntNumber
        }
    }
    
    func broadcastTransaction(hex: String) async throws -> String {
        let hexWithPrefix = hex.hasPrefix("0x") ? hex : "0x\(hex)"
        return try await strRpcCall(method: "author_submitExtrinsic", params: [hexWithPrefix])
    }
    
    func getBalance(coin: Coin) async throws -> (rawBalance: String, priceRate: Double) {
        // Start fetching all information concurrently
        do {
            let cryptoPrice = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
            let rawBalance = String(try await fetchBalance(address: coin.address))
            return (rawBalance,cryptoPrice)
        } catch {
            print("getBalance:: \(error.localizedDescription)")
            throw error
        }
    }
    
    func getGasInfo(fromAddress: String) async throws -> (recentBlockHash: String, currentBlockNumber: BigInt, nonce: Int64, specVersion: UInt32, transactionVersion: UInt32, genesisHash: String) {
        async let recentBlockHash = fetchBlockHash()
        async let nonce = fetchNonce(address: fromAddress)
        async let currentBlockNumber = fetchBlockHeader()
        async let runtime = fetchRuntimeVersion()
        async let genesisHash = fetchGenesisBlockHash()
        return await (try recentBlockHash, try currentBlockNumber, Int64(try nonce), try runtime.specVersion, try runtime.transactionVersion, try genesisHash)
    }
}
