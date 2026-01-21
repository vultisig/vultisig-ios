//
//  BlockaidModels.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/07/2025.
//

import Foundation

// MARK: - Common Models

struct CommonMetadataJson: Codable {
    let type: String
    let url: String

    enum CodingKeys: String, CodingKey {
        case type
        case url
    }

    init(type: String = "wallet", url: String) {
        self.type = type
        self.url = url
    }
}

// MARK: - Solana Transaction Request

struct SolanaScanTransactionRequestJson: Codable {
    let chain: String
    let metadata: CommonMetadataJson
    let options: [String]
    let accountAddress: String
    let encoding: String
    let transactions: [String]
    let method: String

    enum CodingKeys: String, CodingKey {
        case chain
        case metadata
        case options
        case accountAddress = "account_address"
        case encoding
        case transactions
        case method
    }
}

// MARK: - Sui Transaction Request

struct SuiScanTransactionRequestJson: Codable {
    let chain: String
    let metadata: CommonMetadataJson
    let options: [String]
    let accountAddress: String
    let transaction: String

    enum CodingKeys: String, CodingKey {
        case chain
        case metadata
        case options
        case accountAddress = "account_address"
        case transaction
    }
}

// MARK: - Bitcoin Transaction Request

struct BitcoinScanTransactionRequestJson: Codable {
    let chain: String
    let metadata: CommonMetadataJson
    let options: [String]
    let accountAddress: String
    let transaction: String

    enum CodingKeys: String, CodingKey {
        case chain
        case metadata
        case options
        case accountAddress = "account_address"
        case transaction
    }
}

// MARK: - Ethereum Transaction Request

struct EthereumScanTransactionRequestJson: Codable {
    let chain: String
    let metadata: MetadataJson
    let options: [String]
    let accountAddress: String
    let data: DataJson
    let simulatedWithEstimatedGas: Bool

    enum CodingKeys: String, CodingKey {
        case chain
        case metadata
        case options
        case accountAddress = "account_address"
        case data
        case simulatedWithEstimatedGas = "simulate_with_estimated_gas"
    }

    init(chain: String, metadata: MetadataJson, options: [String], accountAddress: String, data: DataJson, simulatedWithEstimatedGas: Bool = false) {
        self.chain = chain
        self.metadata = metadata
        self.options = options
        self.accountAddress = accountAddress
        self.data = data
        self.simulatedWithEstimatedGas = simulatedWithEstimatedGas
    }

    struct MetadataJson: Codable {
        let domain: String

        enum CodingKeys: String, CodingKey {
            case domain
        }
    }

    struct DataJson: Codable {
        let from: String
        let to: String
        let data: String
        let value: String

        enum CodingKeys: String, CodingKey {
            case from
            case to
            case data
            case value
        }
    }
}

// MARK: - Blockaid Transaction Scan Response

struct BlockaidTransactionScanResponseJson: Codable {
    let requestId: String?
    let accountAddress: String?
    let status: String?
    let validation: BlockaidValidationJson?
    let result: BlockaidSolanaResultJson?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case accountAddress = "account_address"
        case status
        case validation
        case result
        case error
    }

    struct BlockaidSolanaResultJson: Codable {
        let validation: BlockaidSolanaValidationJson

        enum CodingKeys: String, CodingKey {
            case validation
        }

        struct BlockaidSolanaValidationJson: Codable {
            let resultType: String
            let reason: String
            let features: [String]
            let extendedFeatures: [BlockaidSolanaExtendedFeaturesJson]

            enum CodingKeys: String, CodingKey {
                case resultType = "result_type"
                case reason
                case features
                case extendedFeatures = "extended_features"
            }

            init(resultType: String, reason: String, features: [String] = [], extendedFeatures: [BlockaidSolanaExtendedFeaturesJson] = []) {
                self.resultType = resultType
                self.reason = reason
                self.features = features
                self.extendedFeatures = extendedFeatures
            }

            struct BlockaidSolanaExtendedFeaturesJson: Codable {
                let type: String
                let description: String

                enum CodingKeys: String, CodingKey {
                    case type
                    case description
                }
            }
        }
    }

    struct BlockaidValidationJson: Codable {
        let status: String?
        let classification: String?
        let resultType: String?
        let description: String?
        let reason: String?
        let features: [BlockaidFeatureJson]?
        let error: String?

        enum CodingKeys: String, CodingKey {
            case status
            case classification
            case resultType = "result_type"
            case description
            case reason
            case features
            case error
        }

        struct BlockaidFeatureJson: Codable {
            let type: String
            let featureId: String
            let description: String
            let address: String?

            enum CodingKeys: String, CodingKey {
                case type
                case featureId = "feature_id"
                case description
                case address
            }
        }
    }
}
