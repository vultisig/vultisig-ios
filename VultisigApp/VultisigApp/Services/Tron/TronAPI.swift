//
//  TronAPI.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/01/2026.
//

import Foundation

enum TronAPI: TargetType {
    case getNowBlock
    case getAccount(address: String)
    case getAccountResource(address: String)
    case getChainParameters
    case broadcastTransaction(jsonString: String)
    case triggerConstantContract(ownerAddress: String, contractAddress: String, functionSelector: String, parameter: String)

    var baseURL: URL {
        URL(string: "https://go.getblock.asia/074e5f95441a40039aa3da010322ecbb")!
    }

    var path: String {
        switch self {
        case .getNowBlock:
            return "/wallet/getnowblock"
        case .getAccount:
            return "/wallet/getaccount"
        case .getAccountResource:
            return "/wallet/getaccountresource"
        case .getChainParameters:
            return "/wallet/getchainparameters"
        case .broadcastTransaction:
            return "/wallet/broadcasttransaction"
        case .triggerConstantContract:
            return "/wallet/triggerconstantcontract"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getNowBlock, .getChainParameters:
            return .get
        case .getAccount, .getAccountResource, .broadcastTransaction, .triggerConstantContract:
            return .post
        }
    }

    var task: HTTPTask {
        switch self {
        case .getNowBlock, .getChainParameters:
            return .requestPlain

        case .getAccount(let address):
            return .requestParameters(
                ["address": address, "visible": true],
                .jsonEncoding
            )

        case .getAccountResource(let address):
            return .requestParameters(
                ["address": address, "visible": true],
                .jsonEncoding
            )

        case .broadcastTransaction(let jsonString):
            guard let data = jsonString.data(using: .utf8) else {
                return .requestPlain
            }
            return .requestData(data)

        case .triggerConstantContract(let ownerAddress, let contractAddress, let functionSelector, let parameter):
            return .requestParameters([
                "owner_address": ownerAddress,
                "contract_address": contractAddress,
                "function_selector": functionSelector,
                "parameter": parameter,
                "visible": true
            ], .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        return [
            "accept": "application/json",
            "content-type": "application/json"
        ]
    }
}

// MARK: - Response Models

struct TronNowBlockResponse: Codable {
    let block_header: TronBlockHeader?

    struct TronBlockHeader: Codable {
        let raw_data: TronBlockRawData?
    }

    struct TronBlockRawData: Codable {
        let timestamp: UInt64?
        let number: UInt64?
        let version: Int?
        let txTrieRoot: String?
        let parentHash: String?
        let witness_address: String?
    }
}

struct TronAccountResponse: Codable {
    let address: String
    let balance: Int64?
    let frozenV2: [TronFrozenV2]?
    let unfrozenV2: [TronUnfrozenV2]?
    
    struct TronFrozenV2: Codable {
        let type: String?  // nil or "BANDWIDTH" = bandwidth, "ENERGY" = energy
        let amount: Int64?
    }
    
    struct TronUnfrozenV2: Codable {
        let unfreeze_amount: Int64?
        let unfreeze_expire_time: Int64?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.address = (try? container.decode(String.self, forKey: .address)) ?? ""
        self.balance = try? container.decode(Int64.self, forKey: .balance)
        self.frozenV2 = try? container.decode([TronFrozenV2].self, forKey: .frozenV2)
        self.unfrozenV2 = try? container.decode([TronUnfrozenV2].self, forKey: .unfrozenV2)
    }

    private enum CodingKeys: String, CodingKey {
        case address
        case balance
        case frozenV2
        case unfrozenV2
    }
    
    /// Returns frozen TRX for bandwidth (in SUN) - sums all bandwidth entries
    var frozenBandwidthSun: Int64 {
        // TRON API: type is nil or "BANDWIDTH" for bandwidth
        return frozenV2?
            .filter { $0.type == nil || $0.type == TronResourceType.bandwidth.rawValue }
            .compactMap { $0.amount }
            .reduce(0, +) ?? 0
    }
    
    /// Returns frozen TRX for energy (in SUN) - sums all energy entries
    var frozenEnergySun: Int64 {
        return frozenV2?
            .filter { $0.type == TronResourceType.energy.rawValue }
            .compactMap { $0.amount }
            .reduce(0, +) ?? 0
    }
    
    /// Returns total TRX in unfreezing process (in SUN) - awaiting withdrawal
    var unfreezingTotalSun: Int64 {
        return unfrozenV2?
            .compactMap { $0.unfreeze_amount }
            .reduce(0, +) ?? 0
    }
}

struct TronAccountResourceResponse: Codable {
    let freeNetUsed: Int64
    let freeNetLimit: Int64
    let NetUsed: Int64
    let NetLimit: Int64
    let EnergyUsed: Int64
    let EnergyLimit: Int64

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.freeNetUsed = (try? container.decode(Int64.self, forKey: .freeNetUsed)) ?? 0
        self.freeNetLimit = (try? container.decode(Int64.self, forKey: .freeNetLimit)) ?? 0
        self.NetUsed = (try? container.decode(Int64.self, forKey: .NetUsed)) ?? 0
        self.NetLimit = (try? container.decode(Int64.self, forKey: .NetLimit)) ?? 0
        self.EnergyUsed = (try? container.decode(Int64.self, forKey: .EnergyUsed)) ?? 0
        self.EnergyLimit = (try? container.decode(Int64.self, forKey: .EnergyLimit)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case freeNetUsed
        case freeNetLimit
        case NetUsed
        case NetLimit
        case EnergyUsed
        case EnergyLimit
    }

    func calculateAvailableBandwidth() -> Int64 {
        let freeBandwidthAvailable = freeNetLimit - freeNetUsed
        let netBandwidthAvailable = NetLimit - NetUsed
        return freeBandwidthAvailable + netBandwidthAvailable
    }
}

struct TronChainParametersResponse: Codable {
    let chainParameter: [TronChainParameter]

    struct TronChainParameter: Codable {
        let key: String
        let value: Int64?
    }

    var bandwidthFeePrice: Int64 {
        chainParameter.first { $0.key == "getTransactionFee" }?.value ?? 1000
    }

    var memoFeeEstimate: Int64 {
        let memoFee = chainParameter.first { $0.key == "getMemoFee" }?.value ?? 0
        return memoFee > 0 ? memoFee : 1_000_000
    }

    var createAccountFeeEstimate: Int64 {
        chainParameter.first { $0.key == "getCreateAccountFee" }?.value ?? 100_000
    }

    var createNewAccountFeeEstimateContract: Int64 {
        chainParameter.first { $0.key == "getCreateNewAccountFeeInSystemContract" }?.value ?? 1_000_000
    }
}

struct TronBroadcastResponse: Codable {
    let result: Bool?
    let txid: String?
    let code: String?
    let message: String?
}

struct TronTriggerConstantResponse: Codable {
    let result: TronTriggerResult?
    let constant_result: [String]?
    let energy_used: Int?
    let energy_penalty: Int?

    struct TronTriggerResult: Codable {
        let result: Bool?
        let message: String?
    }
}
