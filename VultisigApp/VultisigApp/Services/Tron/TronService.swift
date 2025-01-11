//
//  TronService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 02/01/25.
//

import Foundation
import BigInt
import WalletCore

class TronService: RpcService {
    
    static let rpcEndpoint = Endpoint.tronServiceRpc
    static let shared = TronService(rpcEndpoint)
    
    func broadcastTransaction(jsonString: String) async -> Result<String,Error> {
        
        print("Broadcast transaction JSON REQUEST: ")
        print(jsonString)
        
        let url = URL(string: Endpoint.broadcastTransactionTron)!
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            return .failure(HelperError.runtimeError("fail to convert input json to data"))
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        do{
            let (data,resp)  =  try await URLSession.shared.data(for: request)
            
            guard let httpResponse = resp as? HTTPURLResponse else {
                return .failure(HelperError.runtimeError("Invalid http response"))
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure(HelperError.runtimeError("status code:\(httpResponse.statusCode), \(String(data: data, encoding: .utf8) ?? "Unknown error")"))
            }
            
            let response = try JSONDecoder().decode(TronBroadcastResponse.self, from: data)
            
            
            if let txHash = response.txid {
                return .success(txHash)
            }
            
            return .failure(HelperError.runtimeError(String(data: data, encoding: .utf8) ?? "Unknown error"))
            
        }
        catch{
            return .failure(error)
        }
        
    }
    
    func getBlockInfo() async throws -> BlockChainSpecific {
        let body: [String: Any] = [:]
        let dataPayload = try JSONSerialization.data(withJSONObject: body, options: [])
        
        guard let url = URL(string: Endpoint.fetchBlockNowInfoTron) else {
            throw PayloadServiceError.NetworkError(message: "invalid url: \(Endpoint.fetchBlockNowInfoTron)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = dataPayload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, resp) = try await URLSession.shared.data(for: request)
        if let httpResponse = resp as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw PayloadServiceError.NetworkError(message: "fail to fetch block info")
        }
        
        let decoder = JSONDecoder()
        let response = try decoder.decode(TronBlock.self, from: data)
        
        let currentTimestampMillis = UInt64(Date().timeIntervalSince1970 * 1000)
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let oneHourMillis = Int64(60 * 60 * 1000)
        let expiration = nowMillis + oneHourMillis
        
        return BlockChainSpecific.Tron(
            timestamp: currentTimestampMillis,
            expiration: UInt64(expiration),
            blockHeaderTimestamp: response.block_header?.raw_data?.timestamp ?? 0,
            blockHeaderNumber: response.block_header?.raw_data?.number ?? 0,
            blockHeaderVersion: UInt64(response.block_header?.raw_data?.version ?? 0),
            blockHeaderTxTrieRoot: response.block_header?.raw_data?.txTrieRoot ?? "",
            blockHeaderParentHash: response.block_header?.raw_data?.parentHash ?? "",
            blockHeaderWitnessAddress: response.block_header?.raw_data?.witness_address ?? ""
        )
    }
    
    func getBalance(coin: Coin) async throws -> String {
        if coin.isNativeToken {
            // Native TRX balance
            let body: [String: Any] = ["address": coin.address, "visible": true]
            let dataPayload = try JSONSerialization.data(
                withJSONObject: body,
                options: []
            )
            
            let data = try await Utils.asyncPostRequest(
                urlString: Endpoint.fetchAccountInfoTron(),
                headers: [:],
                body: dataPayload
            )
            
            // Attempt to extract the balance as a number first
            if let balanceNumber = Utils.extractResultFromJson(fromData: data, path: "balance") as? NSNumber {
                return balanceNumber.stringValue
            }
            
            // If needed, try extracting as a string fallback (in case API changes)
            if let balanceString = Utils.extractResultFromJson(fromData: data, path: "balance") as? String {
                return balanceString
            }
            
            return "0"
        } else {
            
            guard let hexAddressData = Base58.decode(string: coin.address) else {
                return "0"
            }
            
            let hexAddress = hexAddressData.hexString
            
            
            guard let hexContractAddressData = Base58.decode(string: coin.contractAddress) else {
                return "0"
            }
            
            let hexContractAddress = hexContractAddressData.hexString
            
            let balance = try await TronEvmService.shared.fetchTRC20TokenBalance(
                contractAddress: "0x" + hexContractAddress,
                walletAddress: "0x" + hexAddress
            )
            return String(balance)

        }
    }
    
}

struct TronBroadcastResponse: Codable {
    let txid: String?
    let result: Bool?
}

struct TronBlock: Codable {
    let blockID: String?
    let block_header: BlockHeader?
    
    private enum CodingKeys: String, CodingKey {
        case blockID
        case block_header
    }
    
    struct BlockHeader: Codable {
        let raw_data: RawData?
        let witness_signature: String?
        
        private enum CodingKeys: String, CodingKey {
            case raw_data
            case witness_signature
        }
        
        struct RawData: Codable {
            let number: UInt64?
            let txTrieRoot: String?
            let witness_address: String?
            let parentHash: String?
            let version: Int?
            let timestamp: UInt64?
            
            private enum CodingKeys: String, CodingKey {
                case number, txTrieRoot, witness_address, parentHash, version, timestamp
            }
        }
    }
}

struct TRC20BalanceResponse: Codable {
    let result: ResultStatus
    let constantResult: [String]?
    
    struct ResultStatus: Codable {
        let result: Bool
    }
}
