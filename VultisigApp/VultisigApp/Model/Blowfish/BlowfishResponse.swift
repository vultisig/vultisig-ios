//
//  BlowfishResponse.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 22/07/24.
//

import Foundation

struct BlowfishResponse: Codable {
    let requestId: String?
    let action: String?
    let warnings: [BlowfishWarning]?
    let aggregated: BlowfishAggregatedResults?
    
    enum CodingKeys: String, CodingKey {
        case requestId, action, warnings, aggregated
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
        action = try container.decodeIfPresent(String.self, forKey: .action)
        warnings = try container.decodeIfPresent([BlowfishWarning].self, forKey: .warnings)
        aggregated = try container.decodeIfPresent(BlowfishAggregatedResults.self, forKey: .aggregated)
    }
}

struct BlowfishWarning: Codable, Identifiable {
    let data: String?
    let severity: String?
    let kind: String?
    let message: String?
    
    var id: String { self.message ?? "" }
    
    enum CodingKeys: String, CodingKey {
        case data, severity, kind, message
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decodeIfPresent(String.self, forKey: .data)
        severity = try container.decodeIfPresent(String.self, forKey: .severity)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}

struct BlowfishAggregatedResults: Codable {
    let error: BlowfishSimulationError?
    let action: String?
    let warnings: [BlowfishWarning]?
    
    enum CodingKeys: String, CodingKey {
        case error, action, warnings
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        error = try container.decodeIfPresent(BlowfishSimulationError.self, forKey: .error)
        action = try container.decodeIfPresent(String.self, forKey: .action)
        warnings = try container.decodeIfPresent([BlowfishWarning].self, forKey: .warnings)
    }
}

struct BlowfishSimulationError: Codable {
    let kind: String?
    let humanReadableError: String?
    
    enum CodingKeys: String, CodingKey {
        case kind, humanReadableError
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        humanReadableError = try container.decodeIfPresent(String.self, forKey: .humanReadableError)
    }
}

struct BlowfishStateChange: Codable {
    let value: String?
    let humanReadableDiff: String?
    let rawInfo: RawInfo?
    let suggestedColor: String?
    
    enum CodingKeys: String, CodingKey {
        case value, humanReadableDiff, rawInfo, suggestedColor
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decodeIfPresent(String.self, forKey: .value)
        humanReadableDiff = try container.decodeIfPresent(String.self, forKey: .humanReadableDiff)
        rawInfo = try container.decodeIfPresent(RawInfo.self, forKey: .rawInfo)
        suggestedColor = try container.decodeIfPresent(String.self, forKey: .suggestedColor)
    }
}

struct RawInfo: Codable {
    let kind: String?
    let data: AssetTransferData?
    
    enum CodingKeys: String, CodingKey {
        case kind, data
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        data = try container.decodeIfPresent(AssetTransferData.self, forKey: .data)
    }
}

struct AssetTransferData: Codable {
    let amount: Amount?
    let counterparty: Counterparty?
    let asset: Asset?
    let diff: Diff?
    
    enum CodingKeys: String, CodingKey {
        case amount, counterparty, asset, diff
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        amount = try container.decodeIfPresent(Amount.self, forKey: .amount)
        counterparty = try container.decodeIfPresent(Counterparty.self, forKey: .counterparty)
        asset = try container.decodeIfPresent(Asset.self, forKey: .asset)
        diff = try container.decodeIfPresent(Diff.self, forKey: .diff)
    }
}

struct Amount: Codable {
    let before: String?
    let after: String?
    
    enum CodingKeys: String, CodingKey {
        case before, after
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        before = try container.decodeIfPresent(String.self, forKey: .before)
        after = try container.decodeIfPresent(String.self, forKey: .after)
    }
}

struct Counterparty: Codable {
    let kind: String?
    let address: String?
    
    enum CodingKeys: String, CodingKey {
        case kind, address
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        address = try container.decodeIfPresent(String.self, forKey: .address)
    }
}

struct Asset: Codable {
    let address: String?
    let symbol: String?
    let name: String?
    let decimals: Int?
    let verified: Bool?
    let imageUrl: String?
    let price: Price?
    let supply: Int?
    let metaplexTokenStandard: String?
    let previews: Previews?
    let lists: [String]?
    
    enum CodingKeys: String, CodingKey {
        case address, symbol, name, decimals, verified, imageUrl, price, supply, metaplexTokenStandard, previews, lists
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        decimals = try container.decodeIfPresent(Int.self, forKey: .decimals)
        verified = try container.decodeIfPresent(Bool.self, forKey: .verified)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        price = try container.decodeIfPresent(Price.self, forKey: .price)
        supply = try container.decodeIfPresent(Int.self, forKey: .supply)
        metaplexTokenStandard = try container.decodeIfPresent(String.self, forKey: .metaplexTokenStandard)
        previews = try container.decodeIfPresent(Previews.self, forKey: .previews)
        lists = try container.decodeIfPresent([String].self, forKey: .lists)
    }
}

struct Price: Codable {
    let source: String?
    let updatedAt: Int?
    let dollarValuePerToken: Double?
    
    enum CodingKeys: String, CodingKey {
        case source, updatedAt, dollarValuePerToken
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        updatedAt = try container.decodeIfPresent(Int.self, forKey: .updatedAt)
        dollarValuePerToken = try container.decodeIfPresent(Double.self, forKey: .dollarValuePerToken)
    }
}

struct Previews: Codable {
    let small: String?
    let medium: String?
    let large: String?
    
    enum CodingKeys: String, CodingKey {
        case small, medium, large
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        small = try container.decodeIfPresent(String.self, forKey: .small)
        medium = try container.decodeIfPresent(String.self, forKey: .medium)
        large = try container.decodeIfPresent(String.self, forKey: .large)
    }
}

struct Diff: Codable {
    let sign: String?
    let digits: Int?
    
    enum CodingKeys: String, CodingKey {
        case sign, digits
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sign = try container.decodeIfPresent(String.self, forKey: .sign)
        digits = try container.decodeIfPresent(Int.self, forKey: .digits)
    }
}

struct BlowfishPerTransaction: Codable {
    let error: BlowfishTransactionError?
    let gas: BlowfishGas?
    let protocolInfo: [BlowfishProtocolInfo]?
    let logs: [BlowfishLog]?
    let decodedLogs: [BlowfishDecodedLog]?
    let decodedCalldata: BlowfishDecodedCalldata?
    let isNonceValid: Bool?
    let raw: Raw?
    let instructions: [BlowfishInstruction]?
    
    enum CodingKeys: String, CodingKey {
        case error, gas, protocolInfo, logs, decodedLogs, decodedCalldata, isNonceValid, raw, instructions
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        error = try container.decodeIfPresent(BlowfishTransactionError.self, forKey: .error)
        gas = try container.decodeIfPresent(BlowfishGas.self, forKey: .gas)
        protocolInfo = try container.decodeIfPresent([BlowfishProtocolInfo].self, forKey: .protocolInfo)
        logs = try container.decodeIfPresent([BlowfishLog].self, forKey: .logs)
        decodedLogs = try container.decodeIfPresent([BlowfishDecodedLog].self, forKey: .decodedLogs)
        decodedCalldata = try container.decodeIfPresent(BlowfishDecodedCalldata.self, forKey: .decodedCalldata)
        isNonceValid = try container.decodeIfPresent(Bool.self, forKey: .isNonceValid)
        raw = try container.decodeIfPresent(Raw.self, forKey: .raw)
        instructions = try container.decodeIfPresent([BlowfishInstruction].self, forKey: .instructions)
    }
}

struct BlowfishTransactionError: Codable {
    let kind: String?
    let humanReadableError: String?
    let revertReason: String?
    
    enum CodingKeys: String, CodingKey {
        case kind, humanReadableError, revertReason
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        humanReadableError = try container.decodeIfPresent(String.self, forKey: .humanReadableError)
        revertReason = try container.decodeIfPresent(String.self, forKey: .revertReason)
    }
}

struct BlowfishGas: Codable {
    let gasLimit: String?
    
    enum CodingKeys: String, CodingKey {
        case gasLimit
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gasLimit = try container.decodeIfPresent(String.self, forKey: .gasLimit)
    }
}

struct BlowfishProtocolInfo: Codable {
    let trustLevel: String?
    let name: String?
    let description: String?
    let websiteUrl: String?
    let imageUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case trustLevel, name, description, websiteUrl, imageUrl
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trustLevel = try container.decodeIfPresent(String.self, forKey: .trustLevel)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        websiteUrl = try container.decodeIfPresent(String.self, forKey: .websiteUrl)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
    }
}

struct BlowfishLog: Codable {
    let address: String?
    let topics: [String]?
    let data: LogData?
    
    enum CodingKeys: String, CodingKey {
        case address, topics, data
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        topics = try container.decodeIfPresent([String].self, forKey: .topics)
        data = try container.decodeIfPresent(LogData.self, forKey: .data)
    }
    
    enum LogData: Codable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
        case array([LogData])
        case dictionary([String: LogData])
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .string(string)
            } else if let int = try? container.decode(Int.self) {
                self = .int(int)
            } else if let double = try? container.decode(Double.self) {
                self = .double(double)
            } else if let bool = try? container.decode(Bool.self) {
                self = .bool(bool)
            } else if let array = try? container.decode([LogData].self) {
                self = .array(array)
            } else if let dictionary = try? container.decode([String: LogData].self) {
                self = .dictionary(dictionary)
            } else {
                throw DecodingError.typeMismatch(LogData.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unexpected type"))
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let string):
                try container.encode(string)
            case .int(let int):
                try container.encode(int)
            case .double(let double):
                try container.encode(double)
            case .bool(let bool):
                try container.encode(bool)
            case .array(let array):
                try container.encode(array)
            case .dictionary(let dictionary):
                try container.encode(dictionary)
            }
        }
    }
}

struct BlowfishDecodedLog: Codable {
    let name: String?
    let signature: String?
    let params: [String]?
    
    enum CodingKeys: String, CodingKey {
        case name, signature, params
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        signature = try container.decodeIfPresent(String.self, forKey: .signature)
        params = try container.decodeIfPresent([String].self, forKey: .params)
    }
}

struct BlowfishDecodedCalldata: Codable {
    let kind: String?
    let data: String?
    
    enum CodingKeys: String, CodingKey {
        case kind, data
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        data = try container.decodeIfPresent(String.self, forKey: .data)
    }
}

struct Raw: Codable {
    let err: String?
    let logs: [String]?
    let unitsConsumed: Int?
    let returnData: String?
    
    enum CodingKeys: String, CodingKey {
        case err, logs, unitsConsumed, returnData
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        err = try container.decodeIfPresent(String.self, forKey: .err)
        logs = try container.decodeIfPresent([String].self, forKey: .logs)
        unitsConsumed = try container.decodeIfPresent(Int.self, forKey: .unitsConsumed)
        returnData = try container.decodeIfPresent(String.self, forKey: .returnData)
    }
}

struct BlowfishInstruction: Codable {
    let protocolIndex: Int?
    let topLevelInstruction: String?
    let flattenedInnerInstructions: [String]?
    
    enum CodingKeys: String, CodingKey {
        case protocolIndex, topLevelInstruction, flattenedInnerInstructions
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protocolIndex = try container.decodeIfPresent(Int.self, forKey: .protocolIndex)
        topLevelInstruction = try container.decodeIfPresent(String.self, forKey: .topLevelInstruction)
        flattenedInnerInstructions = try container.decodeIfPresent([String].self, forKey: .flattenedInnerInstructions)
    }
}
