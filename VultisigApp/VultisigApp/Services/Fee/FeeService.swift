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
    case GasFee(price: BigInt, limit: BigInt, amount: BigInt,nonce: Int64)
    case Eip1559(limit: BigInt, maxFeePerGas: BigInt, maxPriorityFeePerGas: BigInt, amount: BigInt,nonce: Int64)
    case BasicFee(amount: BigInt,nonce: Int64,limit: BigInt)
    
    var amount: BigInt {
        switch self {
        case .GasFee(_, _, let amount,_):
            return amount
        case .Eip1559(_, _, _, let amount,_):
            return amount
        case .BasicFee(let amount,_,_):
            return amount
        }
    }
}

protocol FeeService {
    func calculateFees(chain: Chain, limit: BigInt, isSwap: Bool, fromAddress:String,feeMode: FeeMode) async throws -> FeeEnum
}

class EthereumFeeService: FeeService {
    private let chain: Chain
    private let evmService: EvmService
    
    init(chain: Chain) throws {
        self.chain = chain
        self.evmService = try EvmService.getService(forChain: chain)
    }
    
    func calculateFees(chain: Chain, limit: BigInt, isSwap: Bool, fromAddress:String,feeMode: FeeMode) async throws -> FeeEnum {
        let (gasPrice, priorityFee, nonce) = try await self.evmService.getGasInfo(fromAddress: fromAddress, mode: feeMode)
        var newLimit = limit
        if isSwap {
            newLimit = inflatedGasLimit(limit)
        }
        if chain.supportsEip1559 {
            return try await calculateEip1559Fees(limit: newLimit, isSwap: isSwap, priorityFee: priorityFee, chain: chain,nonce: nonce)
        } else {
            return calculateLegacyFees(limit: newLimit, isSwap: isSwap, gasPrice: gasPrice,nonce: nonce)
        }
    }
    
    private func calculateEip1559Fees(limit: BigInt, isSwap: Bool, priorityFee: BigInt, chain: Chain,nonce: Int64) async throws -> FeeEnum {
        let baseFee = try await evmService.getBaseFee()
        
        let calculatedPriorityFee = calculateMaxPriorityFeePerGas(
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
    
    private func calculateLegacyFees(limit: BigInt, isSwap: Bool, gasPrice: BigInt,nonce: Int64) -> FeeEnum {
        let adjustedGasPrice = isSwap ? gasPrice * 110 / 100 : gasPrice
        let amount = adjustedGasPrice * limit
        
        return .GasFee(
            price: adjustedGasPrice,
            limit: limit,
            amount: amount,
            nonce: nonce
        )
    }
    
    private func calculateMaxPriorityFeePerGas(originalPriorityFee: BigInt, chain: Chain) -> BigInt {
        let gwei = BigInt(10).power(9)
        let defaultMaxPriorityFeePerGasL2 = BigInt(20)
        let defaultMaxPriorityFeePolygon = BigInt(30)
        
        switch chain {
        case .avalanche:
            return originalPriorityFee
            
        case .arbitrum, .mantle:
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
        // TODO: - Remove
        return gasLimit
    }
}

enum FeeServiceError: Error {
    case invalidResponse
    case unsupportedChain
}
