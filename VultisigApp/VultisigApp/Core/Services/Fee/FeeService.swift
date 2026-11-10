//
//  FeeService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 03/09/25.
//

import Foundation
import BigInt
import VultisigCommonData

enum FeeEnum {
    case GasFee(price: BigInt, limit: BigInt, amount: BigInt, nonce: Int64)
    case Eip1559(limit: BigInt, maxFeePerGas: BigInt, maxPriorityFeePerGas: BigInt, amount: BigInt, nonce: Int64)
    case BasicFee(amount: BigInt, nonce: Int64, limit: BigInt)

    var amount: BigInt {
        switch self {
        case .GasFee(_, _, let amount, _):
            return amount
        case .Eip1559(_, _, _, let amount, _):
            return amount
        case .BasicFee(let amount, _, _):
            return amount
        }
    }
}

class EthereumFeeService {
    static let ethereumTipRewardPercentile = 75
    static let ethereumSendPriorityFeeFloor = BigInt(200_000_000)
    static let ethereumSwapPriorityFeeFloor = BigInt(500_000_000)

    private let chain: Chain
    private let evmService: EvmService

    init(chain: Chain) throws {
        self.chain = chain
        self.evmService = try EvmService.getService(forChain: chain)
    }

    /// Ethereum mainnet tip for `mode` from recent blocks' rewards: Low takes
    /// the smallest, Normal the median, Fast the largest, each raised to the
    /// send or swap floor. `nil` when there are no rewards.
    static func ethereumPriorityFee(rewards: [BigInt], mode: FeeMode, usesSwapFloor: Bool) -> BigInt? {
        let sorted = rewards.sorted()
        guard let low = sorted.first, let median = sorted.median(), let high = sorted.last else {
            return nil
        }
        let tierTip: BigInt
        switch mode {
        case .safeLow:
            tierTip = low
        case .normal:
            tierTip = median
        case .fast:
            tierTip = high
        }
        return max(tierTip, usesSwapFloor ? ethereumSwapPriorityFeeFloor : ethereumSendPriorityFeeFloor)
    }

    /// The tip each tier signs for an Ethereum mainnet send; `nil` when there are no rewards.
    static func ethereumSendPriorityFees(rewards: [BigInt]) -> [FeeMode: BigInt]? {
        var fees: [FeeMode: BigInt] = [:]
        for mode in FeeMode.allCases {
            guard let fee = ethereumPriorityFee(rewards: rewards, mode: mode, usesSwapFloor: false) else { return nil }
            fees[mode] = fee
        }
        return fees
    }

    /// `usesSwapPriorityFeeFloor` picks Ethereum's swap tip floor only; `isSwap`
    /// keeps its gas-limit and base-fee padding, which THORChain/Maya deposits skip.
    func calculateFees(chain: Chain, limit: BigInt, isSwap: Bool, usesSwapPriorityFeeFloor: Bool, fromAddress: String, feeMode: FeeMode) async throws -> FeeEnum {
        let (gasPrice, priorityFee, nonce) = try await self.evmService.getGasInfo(fromAddress: fromAddress, mode: feeMode)
        var newLimit = limit
        if isSwap {
            newLimit = inflatedGasLimit(limit)
        }
        if chain.supportsEip1559 {
            return try await calculateEip1559Fees(limit: newLimit, isSwap: isSwap, usesSwapPriorityFeeFloor: usesSwapPriorityFeeFloor, priorityFee: priorityFee, feeMode: feeMode, chain: chain, nonce: nonce)
        } else {
            return calculateLegacyFees(limit: newLimit, isSwap: isSwap, gasPrice: gasPrice, nonce: nonce)
        }
    }

    private func calculateEip1559Fees(limit: BigInt, isSwap: Bool, usesSwapPriorityFeeFloor: Bool, priorityFee: BigInt, feeMode: FeeMode, chain: Chain, nonce: Int64) async throws -> FeeEnum {
        async let marketRewards = ethereumMarketRewards()
        let baseFee = try await evmService.getBaseFee()

        let marketTip = try await marketRewards.flatMap {
            Self.ethereumPriorityFee(rewards: $0, mode: feeMode, usesSwapFloor: usesSwapPriorityFeeFloor)
        }
        let calculatedPriorityFee = marketTip ?? calculateMaxPriorityFeePerGas(
            originalPriorityFee: priorityFee,
            chain: chain
        )

        let baseNetworkPrice = isSwap ? (baseFee * 110) / 100 : baseFee
        let maxFeePerGas = (baseNetworkPrice * 120) / 100 + calculatedPriorityFee

        return .Eip1559(
            limit: limit,
            maxFeePerGas: maxFeePerGas,
            maxPriorityFeePerGas: calculatedPriorityFee,
            amount: limit * maxFeePerGas,
            nonce: nonce
        )
    }

    private func calculateLegacyFees(limit: BigInt, isSwap: Bool, gasPrice: BigInt, nonce: Int64) -> FeeEnum {
        let adjustedGasPrice = isSwap ? gasPrice * 110 / 100 : gasPrice
        let amount = adjustedGasPrice * limit

        return .GasFee(
            price: adjustedGasPrice,
            limit: limit,
            amount: amount,
            nonce: nonce
        )
    }

    /// Recent blocks' tip rewards that price Ethereum mainnet, or `nil` off
    /// mainnet or when the read fails.
    func ethereumMarketRewards() async throws -> [BigInt]? {
        guard chain == .ethereum else { return nil }
        do {
            return try await evmService.getFeeHistory(rewardPercentile: Self.ethereumTipRewardPercentile)
        } catch let error as CancellationError {
            throw error
        } catch {
            // No market data: callers keep their pre-existing tip rule.
            return nil
        }
    }

    private func calculateMaxPriorityFeePerGas(originalPriorityFee: BigInt, chain: Chain) -> BigInt {
        let gwei = BigInt(10).power(9)
        let defaultMaxPriorityFeePerGasL2 = BigInt(20)
        let defaultMaxPriorityFeePolygon = BigInt(30)

        switch chain {
        case .avalanche:
            return originalPriorityFee

        case .arbitrum, .mantle, .robinhood:
            return BigInt.zero

        case .base, .blast, .optimism:
            return max(originalPriorityFee, defaultMaxPriorityFeePerGasL2)

        case .polygon:
            return max(originalPriorityFee, gwei * defaultMaxPriorityFeePolygon)

        default:
            return max(originalPriorityFee, gwei)
        }
    }

    func inflatedGasLimit(_ gasLimit: BigInt) -> BigInt {
        return gasLimit + (gasLimit / 2) // add 50%
    }
}
