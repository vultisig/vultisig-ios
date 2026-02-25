//
//  TransactionStatus.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation

enum TransactionStatus: Equatable {
    case broadcasted(estimatedTime: String)
    case pending
    case confirmed
    case failed(reason: String)
    case timeout

    var isTerminal: Bool {
        switch self {
        case .confirmed, .failed, .timeout:
            return true
        default:
            return false
        }
    }

    var persistenceString: String {
        switch self {
        case .broadcasted: return "broadcasted"
        case .pending: return "pending"
        case .confirmed: return "confirmed"
        case .failed: return "failed"
        case .timeout: return "timeout"
        }
    }
}

struct TransactionStatusResult {
    let status: TransactionConfirmationStatus
    let blockNumber: Int?
    let confirmations: Int?

    enum TransactionConfirmationStatus {
        case notFound
        case pending
        case confirmed
        case failed(reason: String)
    }
}

struct ChainStatusConfig {
    let estimatedTime: String
    let pollInterval: TimeInterval
    let maxWaitTime: TimeInterval

    static func config(for chain: Chain) -> ChainStatusConfig {
        switch chain {
        // EVM chains
        case .ethereum, .avalanche, .bscChain, .polygon, .polygonV2,
             .arbitrum, .base, .optimism, .blast, .cronosChain,
             .zksync, .ethereumSepolia, .mantle, .hyperliquid, .sei:
            return ChainStatusConfig(
                estimatedTime: "~15-30 sec",
                pollInterval: 5,
                maxWaitTime: 600  // 10 min
            )

        // UTXO chains
        case .bitcoin:
            return ChainStatusConfig(
                estimatedTime: "~10-60 min",
                pollInterval: 30,
                maxWaitTime: 7200  // 2 hours
            )
        case .litecoin:
            return ChainStatusConfig(
                estimatedTime: "~2-5 min",
                pollInterval: 15,
                maxWaitTime: 1800  // 30 min
            )
        case .dogecoin:
            return ChainStatusConfig(
                estimatedTime: "~1-2 min",
                pollInterval: 10,
                maxWaitTime: 1200  // 20 min
            )
        case .bitcoinCash, .dash:
            return ChainStatusConfig(
                estimatedTime: "~10 min",
                pollInterval: 20,
                maxWaitTime: 3600  // 1 hour
            )
        case .zcash:
            return ChainStatusConfig(
                estimatedTime: "~2.5 min",
                pollInterval: 15,
                maxWaitTime: 1800  // 30 min
            )

        // Cosmos chains
        case .thorChain, .thorChainChainnet, .thorChainStagenet, .mayaChain:
            return ChainStatusConfig(
                estimatedTime: "~6 sec",
                pollInterval: 3,
                maxWaitTime: 300  // 5 min
            )
        case .gaiaChain, .kujira, .osmosis, .terra, .terraClassic,
             .dydx, .noble, .akash:
            return ChainStatusConfig(
                estimatedTime: "~6 sec",
                pollInterval: 3,
                maxWaitTime: 300  // 5 min
            )

        // Other chains
        case .solana:
            return ChainStatusConfig(
                estimatedTime: "~1-2 sec",
                pollInterval: 2,
                maxWaitTime: 120  // 2 min
            )
        case .sui:
            return ChainStatusConfig(
                estimatedTime: "~2-3 sec",
                pollInterval: 2,
                maxWaitTime: 120  // 2 min
            )
        case .ton:
            return ChainStatusConfig(
                estimatedTime: "~5 sec",
                pollInterval: 3,
                maxWaitTime: 300  // 5 min
            )
        case .polkadot:
            return ChainStatusConfig(
                estimatedTime: "~6 sec",
                pollInterval: 3,
                maxWaitTime: 300  // 5 min
            )
        case .cardano:
            return ChainStatusConfig(
                estimatedTime: "~20 sec",
                pollInterval: 5,
                maxWaitTime: 600  // 10 min
            )
        case .ripple:
            return ChainStatusConfig(
                estimatedTime: "~3-5 sec",
                pollInterval: 2,
                maxWaitTime: 300  // 5 min
            )
        case .tron:
            return ChainStatusConfig(
                estimatedTime: "~3 sec",
                pollInterval: 2,
                maxWaitTime: 300  // 5 min
            )
        }
    }
}
