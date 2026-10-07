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

    /// Surfaces the broadcast-time copy on the `broadcasted` branch so callers
    /// re-deriving a `TransactionStatus` (e.g. the SwapKit `/track` mapping on
    /// the swap done-screen) can preserve the original estimate.
    var broadcastedEstimatedTime: String {
        switch self {
        case .broadcasted(let estimatedTime):
            return estimatedTime
        case .pending, .confirmed, .failed, .timeout:
            return ""
        }
    }
}

struct TransactionStatusResult {
    let status: TransactionConfirmationStatus
    let blockNumber: Int?
    let confirmations: Int?
    /// Actual fee paid on-chain in the chain's base units, when the status
    /// provider can prove it. TON fills this from `total_fees` in nanotons;
    /// callers keep their estimated-fee fallback when this is `nil`.
    let paidNetworkFeeBaseUnits: String?

    init(
        status: TransactionConfirmationStatus,
        blockNumber: Int?,
        confirmations: Int?,
        paidNetworkFeeBaseUnits: String? = nil
    ) {
        self.status = status
        self.blockNumber = blockNumber
        self.confirmations = confirmations
        self.paidNetworkFeeBaseUnits = paidNetworkFeeBaseUnits
    }

    enum TransactionConfirmationStatus: Equatable {
        case notFound
        case pending
        case confirmed
        case failed(reason: String)
    }
}

extension TransactionStatusResult {
    func paidNetworkFeeCrypto(for chain: Chain) -> String? {
        guard chain == .ton, let paidNetworkFeeBaseUnits else { return nil }
        return Self.formatTonNetworkFee(nanotons: paidNetworkFeeBaseUnits)
    }

    static func formatTonNetworkFee(nanotons: String) -> String? {
        guard !nanotons.isEmpty,
              nanotons.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }) else {
            return nil
        }

        let ticker = TokensStore.ton.ticker
        let trimmed = String(nanotons.drop { $0 == "0" })
        guard !trimmed.isEmpty else { return "0 \(ticker)" }

        let scale = 9
        if trimmed.count <= scale {
            let padding = String(repeating: "0", count: scale - trimmed.count)
            let fraction = trimmingTrailingZeros(from: padding + trimmed)
            return "0.\(fraction) \(ticker)"
        }

        let splitIndex = trimmed.index(trimmed.endIndex, offsetBy: -scale)
        let whole = String(trimmed[..<splitIndex])
        let fraction = trimmingTrailingZeros(from: String(trimmed[splitIndex...]))
        return fraction.isEmpty ? "\(whole) \(ticker)" : "\(whole).\(fraction) \(ticker)"
    }

    private static func trimmingTrailingZeros(from value: String) -> String {
        var result = value
        while result.last == "0" {
            result.removeLast()
        }
        return result
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
             .zksync, .ethereumSepolia, .mantle, .hyperliquid, .sei, .robinhood:
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
             .dydx, .noble, .akash, .qbtc:
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
        case .bittensor:
            return ChainStatusConfig(
                estimatedTime: "~12 sec",
                pollInterval: 4,
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
        case .near:
            // One block per ~1s, and `FINAL` execution is available in the same
            // block for a native transfer (a transfer has a single receipt).
            return ChainStatusConfig(
                estimatedTime: "~2-3 sec",
                pollInterval: 2,
                maxWaitTime: 120  // 2 min
            )
        }
    }
}
