//
//  PolkadotService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 28/04/24.
//

import Foundation
import BigInt
import VultisigCommonData
import WalletCore

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
        let result = try await strRpcCall(method: "author_submitExtrinsic", params: [hexWithPrefix])
        return result
    }
    
    func getBalance(address: String) async throws -> String {
        let balance = try await fetchBalance(address: address)
        return String(balance)
    }
    
    func getGasInfo(fromAddress: String) async throws -> (recentBlockHash: String, currentBlockNumber: BigInt, nonce: Int64, specVersion: UInt32, transactionVersion: UInt32, genesisHash: String) {
        async let recentBlockHash = fetchBlockHash()
        async let nonce = fetchNonce(address: fromAddress)
        async let currentBlockNumber = fetchBlockHeader()
        async let runtime = fetchRuntimeVersion()
        async let genesisHash = fetchGenesisBlockHash()
        return await (try recentBlockHash, try currentBlockNumber, Int64(try nonce), try runtime.specVersion, try runtime.transactionVersion, try genesisHash)
    }
    
    func getPartialFee(serializedTransaction: String) async throws -> BigInt {
        let hexWithPrefix = serializedTransaction.hasPrefix("0x") ? serializedTransaction : "0x\(serializedTransaction)"
        
        return try await sendRPCRequest(method: "payment_queryInfo", params: [hexWithPrefix]) { result in
            // Handle error message string (from sendRPCRequest error handling)
            if let errorMessage = result as? String {
                throw RpcServiceError.rpcError(code: 500, message: "RPC error: \(errorMessage)")
            }
            
            guard let resultDict = result as? [String: Any] else {
                throw RpcServiceError.rpcError(code: 500, message: "Error to convert the RPC result to Dictionary. Got type: \(type(of: result))")
            }
            
            // Check for error in result
            if let error = resultDict["error"] as? [String: Any] {
                let errorMessage = error["message"] as? String ?? "Unknown error"
                let errorCode = error["code"] as? Int ?? -1
                throw RpcServiceError.rpcError(code: errorCode, message: errorMessage)
            }
            
            guard let partialFeeString = resultDict["partialFee"] as? String else {
                throw RpcServiceError.rpcError(code: 404, message: "partialFee not found in the response. Available keys: \(resultDict.keys)")
            }
            
            guard let partialFee = BigInt(partialFeeString) else {
                throw RpcServiceError.rpcError(code: 500, message: "Error to convert partialFee to BigInt: '\(partialFeeString)'")
            }
            
            return partialFee
        }
    }
    
    func calculateDynamicFee(fromAddress: String, toAddress: String, amount: BigInt, memo: String? = nil) async throws -> BigInt {
        // Validate and use a default address if toAddress is empty or invalid
        let validToAddress: String
        if toAddress.isEmpty {
            validToAddress = fromAddress
        } else {
            // Try to validate the address format
            if let _ = AnyAddress(string: toAddress, coin: .polkadot) {
                validToAddress = toAddress
            } else {
                validToAddress = fromAddress
            }
        }
        
        let gasInfo = try await getGasInfo(fromAddress: fromAddress)
        
        guard let polkadotCoin = TokensStore.TokenSelectionAssets.first(where: { $0.chain == .polkadot && $0.isNativeToken }) else {
            throw HelperError.runtimeError("Polkadot coin not found")
        }
        
        let coin = Coin(asset: polkadotCoin, address: fromAddress, hexPublicKey: "")
        
        let keysignPayload = KeysignPayload(
            coin: coin,
            toAddress: validToAddress,
            toAmount: amount,
            chainSpecific: .Polkadot(
                recentBlockHash: gasInfo.recentBlockHash,
                nonce: UInt64(gasInfo.nonce),
                currentBlockNumber: gasInfo.currentBlockNumber,
                specVersion: gasInfo.specVersion,
                transactionVersion: gasInfo.transactionVersion,
                genesisHash: gasInfo.genesisHash
            ),
            utxos: [],
            memo: memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "",
            libType: "",
            wasmExecuteContractPayload: nil,
            skipBroadcast: false,
            signData: nil
        )
        
        let serializedTransaction: String
        do {
            serializedTransaction = try PolkadotHelper.getZeroSignedTransaction(keysignPayload: keysignPayload)
        } catch {
            throw error
        }
        
        var partialFee = BigInt(250000000)
        do{
            partialFee = try await getPartialFee(serializedTransaction: serializedTransaction)
        } catch {
            print("PolkadotService > calculateDynamicFee > Error fetching partial fee: \(error)")
        }
        
        return partialFee
    }
}
