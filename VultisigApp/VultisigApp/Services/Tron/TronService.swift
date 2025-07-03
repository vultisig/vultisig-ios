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
    
    func getBlockInfo(coin: Coin) async throws -> BlockChainSpecific {
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
        
        var estimation = "100000" // 0.1 TRX = 100000 SUN (default fee for native TRX transfers)
        if !coin.isNativeToken {
            // 0x9c9d70d46934c98fd3d7c302c4e0b924da7a4fdf
            // Tron does not have a 0x... it can be any address
            // We will only simulate the transaction fee with this address
            estimation = try await getTriggerConstantContractFee(ownerAddressBase58:coin.address, contractAddressBase58: coin.contractAddress, recipientAddressHex: "0x9c9d70d46934c98fd3d7c302c4e0b924da7a4fdf", amount: BigUInt(coin.rawBalance.toBigInt()))
        }
        
        return BlockChainSpecific.Tron(
            timestamp: currentTimestampMillis,
            expiration: UInt64(expiration),
            blockHeaderTimestamp: response.block_header?.raw_data?.timestamp ?? 0,
            blockHeaderNumber: response.block_header?.raw_data?.number ?? 0,
            blockHeaderVersion: UInt64(response.block_header?.raw_data?.version ?? 0),
            blockHeaderTxTrieRoot: response.block_header?.raw_data?.txTrieRoot ?? "",
            blockHeaderParentHash: response.block_header?.raw_data?.parentHash ?? "",
            blockHeaderWitnessAddress: response.block_header?.raw_data?.witness_address ?? "",
            gasFeeEstimation: UInt64(estimation) ?? 0
        )
    }
    
    /// Builds the 64-byte hex parameter for `transfer(address,uint256)`.
    /// - Parameters:
    ///   - recipientBase58: TRON base58-check encoded address (e.g., "TVNtPmF7...")
    ///   - amount: The amount to transfer (in decimal), e.g. 1000000
    /// - Returns: A 64-byte hex string suitable for the TRC20 `parameter` field.
    func buildTrc20TransferParameter(recipientBaseHex: String, amount: BigUInt) throws -> String {

        // "000000000000000000000000" + 20-byte hex = total 64 hex chars
        let paddedAddressHex = String(repeating: "0", count: 24) + recipientBaseHex.stripHexPrefix()  // 24 + 40 = 64 hex
        
        // 4) Convert the amount to hex, then left-pad it to 64 hex digits
        let amountHex = String(amount, radix: 16)  // e.g. "f4240" for 1000000
        let paddedAmountHex = String(
            repeating: "0",
            count: max(0, 64 - amountHex.count)
        ) + amountHex
        
        // 5) Concatenate the two 32-byte segments (64 hex chars + 64 hex chars = 128 hex chars total)
        return paddedAddressHex + paddedAmountHex
    }
    
    /// Computes the TRX fee for calling the TRC20 `transfer(address,uint256)` method.
    ///
    /// Fee is calculated as: (energy_used + energy_penalty) * 280 SUN.
    /// 1 TRX = 1,000,000 SUN.
    func getTriggerConstantContractFee(
        ownerAddressBase58: String,           // e.g. "TVNtPmF7JWw4xoA8GAxEZhCaw2khYn8viH"
        contractAddressBase58: String,        // e.g. "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
        recipientAddressHex: String,       // e.g. "9c9d70d46934c98fd3d7c302c4e0b924da7a4fdf" in Base58 remove the prefix 41
        amount: BigUInt                 // e.g. 1_000_000 for 1 token (depends on token decimals)
    ) async throws -> String {
        
        // 1. Build the `function_selector`
        let functionSelector = "transfer(address,uint256)"
        
        // 2. Build the 64-byte `parameter` from recipient + amount
        let parameter = try buildTrc20TransferParameter(
            recipientBaseHex: recipientAddressHex,
            amount: amount
        )
        
        // 3. Create JSON body for the request
        let body: [String: Any] = [
            "owner_address": ownerAddressBase58,
            "contract_address": contractAddressBase58,
            "function_selector": functionSelector,
            "parameter": parameter,
            "visible": true
        ]
        
        let dataPayload = try JSONSerialization.data(withJSONObject: body, options: [])
        
        // 4. Make the POST request (using your existing utility)
        let data = try await Utils.asyncPostRequest(
            urlString: Endpoint.triggerSolidityConstantContractTron(),
            headers: [
                "accept": "application/json",
                "content-type": "application/json"
            ],
            body: dataPayload
        )
        
        // 5. Extract `energy_used` & `energy_penalty`
        guard let energyUsed = Utils.extractResultFromJson(fromData: data, path: "energy_used") as? NSNumber,
              let energyPenalty = Utils.extractResultFromJson(fromData: data, path: "energy_penalty") as? NSNumber
        else {
            // If these fields are not found, handle error or return 0.
            return "0"
        }

        // 6. Calculate fee in SUN and convert to TRX
        let totalEnergy = energyUsed.intValue + energyPenalty.intValue
        let totalSun = totalEnergy * 280
        //let feeTRX = Double(totalSun) / 1_000_000.0
        
        return totalSun.description
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
            
            // Use EvmServiceFactory instead of direct service access
            let evmService = try EvmServiceFactory.getService(forChain: coin.chain)
            let balance = try await evmService.fetchTRC20TokenBalance(
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
