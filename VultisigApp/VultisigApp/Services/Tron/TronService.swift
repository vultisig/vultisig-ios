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
    
    // Cache for chain parameters
    private var chainParametersCache: TronChainParametersResponse?
    
    // Constants from Android implementation
    private static let BYTES_PER_COIN_TX: Int64 = 300
    private static let BYTES_PER_CONTRACT_TX: Int64 = 345
    
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
    
    func getBlockInfo(coin: Coin, to: String? = nil, memo: String? = nil) async throws -> BlockChainSpecific {
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
        
        // Use new sophisticated fee calculation (Android parity)
        let calculatedFee = try await calculateTronFee(coin: coin, to: to, memo: memo)
        let estimation = String(calculatedFee)
        
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
    
    func buildTrc20TransferParameter(recipientBaseHex: String, amount: BigUInt) throws -> String {

        let cleanHex = recipientBaseHex.stripHexPrefix()
        let addressWithoutTronPrefix = cleanHex.count >= 2 ? String(cleanHex.dropFirst(2)) : cleanHex
        let paddedAddressHex = String(repeating: "0", count: max(0, 64 - addressWithoutTronPrefix.count)) + addressWithoutTronPrefix
        
        let amountHex = String(amount, radix: 16)
        let paddedAmountHex = String(
            repeating: "0",
            count: max(0, 64 - amountHex.count)
        ) + amountHex
        return paddedAddressHex + paddedAmountHex
    }
    
    func getTriggerConstantContractFee(
        ownerAddressBase58: String,
        contractAddressBase58: String,
        recipientAddressHex: String,
        amount: BigUInt
    ) async throws -> String {
        let functionSelector = "transfer(address,uint256)"
        let parameter = try buildTrc20TransferParameter(
            recipientBaseHex: recipientAddressHex,
            amount: amount
        )
        let body: [String: Any] = [
            "owner_address": ownerAddressBase58,
            "contract_address": contractAddressBase58,
            "function_selector": functionSelector,
            "parameter": parameter,
            "visible": true
        ]
        
        let dataPayload = try JSONSerialization.data(withJSONObject: body, options: [])
        let data = try await Utils.asyncPostRequest(
            urlString: Endpoint.triggerSolidityConstantContractTron(),
            headers: [
                "accept": "application/json",
                "content-type": "application/json"
            ],
            body: dataPayload
        )
        
        guard let energyUsed = Utils.extractResultFromJson(fromData: data, path: "energy_used") as? NSNumber,
              let energyPenalty = Utils.extractResultFromJson(fromData: data, path: "energy_penalty") as? NSNumber
        else {
            return "0"
        }

        let totalEnergy = energyUsed.intValue + energyPenalty.intValue
        let totalSun = totalEnergy * 280
        return totalSun.description
    }
    
    func getChainParameters() async throws -> TronChainParametersResponse {
        let body: [String: Any] = [:]
        let dataPayload = try JSONSerialization.data(withJSONObject: body, options: [])
        
        guard let url = URL(string: Endpoint.tronServiceRpc + "/wallet/getchainparameters") else {
            throw PayloadServiceError.NetworkError(message: "invalid chain parameters url")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = dataPayload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, resp) = try await URLSession.shared.data(for: request)
        if let httpResponse = resp as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw PayloadServiceError.NetworkError(message: "fail to fetch chain parameters")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(TronChainParametersResponse.self, from: data)
    }
    
    func getAccountResource(address: String) async throws -> TronAccountResourceResponse {
        let body = TronAccountRequest(address: address, visible: true)
        let dataPayload = try JSONEncoder().encode(body)
        
        guard let url = URL(string: Endpoint.tronServiceRpc + "/wallet/getaccountresource") else {
            throw PayloadServiceError.NetworkError(message: "invalid account resource url")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = dataPayload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, resp) = try await URLSession.shared.data(for: request)
        if let httpResponse = resp as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw PayloadServiceError.NetworkError(message: "fail to fetch account resource")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(TronAccountResourceResponse.self, from: data)
    }
    
    func getAccount(address: String) async throws -> TronAccountResponse {
        let body = TronAccountRequest(address: address, visible: true)
        let dataPayload = try JSONEncoder().encode(body)
        
        guard let url = URL(string: Endpoint.tronServiceRpc + "/wallet/getaccount") else {
            throw PayloadServiceError.NetworkError(message: "invalid get account url")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = dataPayload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, resp) = try await URLSession.shared.data(for: request)
        if let httpResponse = resp as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw PayloadServiceError.NetworkError(message: "fail to fetch account")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(TronAccountResponse.self, from: data)
    }
    
    private func getCachedChainParameters() async throws -> TronChainParametersResponse {
        if let cached = chainParametersCache {
            return cached
        }
        
        let parameters = try await getChainParameters()
        chainParametersCache = parameters
        return parameters
    }
    
    private func getBandwidthFeeDiscount(isNativeToken: Bool, availableBandwidth: Int64) async throws -> BigInt {
        let feeBandwidthRequired = isNativeToken ? Self.BYTES_PER_COIN_TX : Self.BYTES_PER_CONTRACT_TX
        let chainParams = try await getCachedChainParameters()
        let bandwidthPrice = chainParams.bandwidthFeePrice
        
        switch (isNativeToken, availableBandwidth >= feeBandwidthRequired) {
        case (true, true):
            // Native transfer with sufficient bandwidth => FREE tx
            return BigInt.zero
        case (false, _):
            // TRC20 always pays fee (no free bandwidth for smart contracts)
            return BigInt(feeBandwidthRequired * bandwidthPrice)
        case (true, false):
            // Native transfer without sufficient bandwidth
            return BigInt(feeBandwidthRequired * bandwidthPrice)
        }
    }
    
    private func getTronFeeMemo(memo: String?) async throws -> BigInt {
        guard let memo = memo, !memo.isEmpty else {
            return BigInt.zero
        }
        
        let chainParams = try await getCachedChainParameters()
        return BigInt(chainParams.memoFeeEstimate)
    }
    
    private func getTronInactiveDestinationFee(to: String?) async throws -> BigInt {
        guard let to = to, !to.isEmpty else {
            return BigInt.zero
        }
        
        let accountExists: Bool
        do {
            let account = try await getAccount(address: to)
            accountExists = !account.address.isEmpty
        } catch {
            accountExists = false
        }
        
        if accountExists {
            return BigInt.zero
        }
        
        let chainParams = try await getCachedChainParameters()
        let createAccountFee = BigInt(chainParams.createAccountFeeEstimate)
        let createAccountContractFee = BigInt(chainParams.createNewAccountFeeEstimateContract)
        
        return createAccountFee + createAccountContractFee
    }
    
    func calculateTronFee(coin: Coin, to: String?, memo: String?) async throws -> BigInt {
        do {
            // Calculate memo fee
            let memoFee = try await getTronFeeMemo(memo: memo)
            
            // Check if destination needs activation (new account)
            let activationFee = try await getTronInactiveDestinationFee(to: to)
            let isNewAccount = activationFee > BigInt.zero
            
            // Calculate bandwidth and energy fees based on token type
            let transactionFee: BigInt
            if coin.isNativeToken {
                // Native TRX: Calculate bandwidth fees only
                let accountResource = try await getAccountResource(address: coin.address)
                let availableBandwidth = accountResource.calculateAvailableBandwidth()
                
                // New accounts don't pay bandwidth fee (included in activation)
                if isNewAccount {
                    transactionFee = BigInt.zero
                } else {
                    transactionFee = try await getBandwidthFeeDiscount(
                        isNativeToken: true,
                        availableBandwidth: availableBandwidth
                    )
                }
            } else {
                let accountResource = try await getAccountResource(address: coin.address)
                let availableEnergy = accountResource.EnergyLimit - accountResource.EnergyUsed
                
                if availableEnergy >= 130000 {
                    transactionFee = BigInt(1_000_000)
                } else {
                    transactionFee = BigInt(28_000_000)
                }
            }
            
            let totalFee = transactionFee + memoFee + activationFee
            return totalFee
            
        } catch {
            return BigInt(Self.BYTES_PER_CONTRACT_TX * 1000)
        }
    }
    
    func getBalance(coin: Coin) async throws -> String {
        if coin.isNativeToken {
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
            
            if let balanceNumber = Utils.extractResultFromJson(fromData: data, path: "balance") as? NSNumber {
                return balanceNumber.stringValue
            }
            
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

struct TronChainParametersResponse: Codable {
    let chainParameter: [TronChainParameter]
    
    private var chainParameterMapped: [String: Int64] {
        Dictionary(uniqueKeysWithValues: chainParameter.map { ($0.key, $0.value) })
    }
    
    var memoFeeEstimate: Int64 {
        chainParameterMapped["getMemoFee"] ?? 0
    }
    
    var createAccountFeeEstimate: Int64 {
        chainParameterMapped["getCreateAccountFee"] ?? 0
    }
    
    var createNewAccountFeeEstimateContract: Int64 {
        chainParameterMapped["getCreateNewAccountFeeInSystemContract"] ?? 0
    }
    
    var bandwidthFeePrice: Int64 {
        chainParameterMapped["getTransactionFee"] ?? 0
    }
}

struct TronChainParameter: Codable {
    let key: String
    let value: Int64
}

struct TronAccountResourceResponse: Codable {
    let freeNetUsed: Int64
    let freeNetLimit: Int64
    let NetUsed: Int64
    let NetLimit: Int64
    let EnergyLimit: Int64
    let EnergyUsed: Int64
    let TotalNetLimit: Int64
    let TotalNetWeight: Int64
    let TotalEnergyLimit: Int64
    let TotalEnergyWeight: Int64
    let tronPowerUsed: Int64
    let tronPowerLimit: Int64
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        freeNetUsed = try container.decodeIfPresent(Int64.self, forKey: .freeNetUsed) ?? 0
        freeNetLimit = try container.decodeIfPresent(Int64.self, forKey: .freeNetLimit) ?? 0
        NetUsed = try container.decodeIfPresent(Int64.self, forKey: .NetUsed) ?? 0
        NetLimit = try container.decodeIfPresent(Int64.self, forKey: .NetLimit) ?? 0
        EnergyLimit = try container.decodeIfPresent(Int64.self, forKey: .EnergyLimit) ?? 0
        EnergyUsed = try container.decodeIfPresent(Int64.self, forKey: .EnergyUsed) ?? 0
        TotalNetLimit = try container.decodeIfPresent(Int64.self, forKey: .TotalNetLimit) ?? 0
        TotalNetWeight = try container.decodeIfPresent(Int64.self, forKey: .TotalNetWeight) ?? 0
        TotalEnergyLimit = try container.decodeIfPresent(Int64.self, forKey: .TotalEnergyLimit) ?? 0
        TotalEnergyWeight = try container.decodeIfPresent(Int64.self, forKey: .TotalEnergyWeight) ?? 0
        tronPowerUsed = try container.decodeIfPresent(Int64.self, forKey: .tronPowerUsed) ?? 0
        tronPowerLimit = try container.decodeIfPresent(Int64.self, forKey: .tronPowerLimit) ?? 0
    }
    
    func calculateAvailableBandwidth() -> Int64 {
        let freeBandwidth = freeNetLimit - freeNetUsed
        let stakingBandwidth = NetLimit - NetUsed
        return freeBandwidth + stakingBandwidth
    }
}

struct TronAccountRequest: Codable {
    let address: String
    let visible: Bool
}

struct TronAccountResponse: Codable {
    let address: String
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try container.decodeIfPresent(String.self, forKey: .address) ?? ""
    }
}
