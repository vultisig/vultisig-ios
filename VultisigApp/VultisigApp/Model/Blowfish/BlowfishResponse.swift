//
//  BlowfishResponse.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 22/07/24.
//

struct BlowfishResponse: Codable {
    let requestId: String
    let action: String
    let warnings: [BlowfishWarning]
    let simulationResults: BlowfishSimulationResults?
    
    struct BlowfishWarning: Codable {
        let data: String?
        let severity: String
        let kind: String
        let message: String
    }
    
    struct BlowfishSimulationResults: Codable {
        let aggregated: BlowfishAggregatedResults?
        let perTransaction: [BlowfishPerTransaction]?
        
        struct BlowfishAggregatedResults: Codable {
            let error: BlowfishSimulationError?
            let expectedStateChanges: [String: [BlowfishStateChange]]?
            let userAccount: String?
        }
        
        struct BlowfishSimulationError: Codable {
            let kind: String?
            let humanReadableError: String?
        }
        
        struct BlowfishStateChange: Codable {
            let value: String?
            let humanReadableDiff: String?
            let rawInfo: RawInfo?
        }
        
        struct RawInfo: Codable {
            let kind: String?
            let data: AssetTransferData?
        }
        
        struct AssetTransferData: Codable {
            let amount: Amount?
            let counterparty: Counterparty?
            let asset: Asset?
        }
        
        struct Amount: Codable {
            let before: String?
            let after: String?
        }
        
        struct Counterparty: Codable {
            let kind: String?
            let address: String?
        }
        
        struct Asset: Codable {
            let address: String?
            let symbol: String?
            let name: String?
            let decimals: Int?
            let verified: Bool?
            let imageUrl: String?
            let price: Price?
        }
        
        struct Price: Codable {
            let source: String?
            let updatedAt: Int?
            let dollarValuePerToken: Double?
        }
        
        struct BlowfishPerTransaction: Codable {
            let error: BlowfishTransactionError?
            let gas: BlowfishGas?
            let protocolInfo: BlowfishProtocolInfo?
            let logs: [BlowfishLog]?
            let decodedLogs: [BlowfishDecodedLog]?
            let decodedCalldata: BlowfishDecodedCalldata?
        }
        
        struct BlowfishTransactionError: Codable {
            let kind: String?
            let humanReadableError: String?
            let revertReason: String?
        }
        
        struct BlowfishGas: Codable {
            let gasLimit: String?
        }
        
        struct BlowfishProtocolInfo: Codable {
            let trustLevel: String?
            let name: String?
            let description: String?
            let websiteUrl: String?
            let imageUrl: String?
        }
        
        struct BlowfishLog: Codable {
            let address: String?
            let topics: [String]?
            let data: LogData?
            
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
        }
        
        struct BlowfishDecodedCalldata: Codable {
            let kind: String?
            let data: String?
        }
    }
}

extension BlowfishResponse.BlowfishWarning: Identifiable {
    public var id: String { self.message } // Assuming `message` is a unique identifier
}
