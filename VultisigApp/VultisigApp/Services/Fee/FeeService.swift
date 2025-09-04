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
    case GasFee(price: BigInt, limit: BigInt, amount: BigInt)
    case Eip1559(limit: BigInt, maxFeePerGas: BigInt, maxPriorityFeePerGas: BigInt, amount: BigInt)
    case BasicFee(amount: BigInt)
    
    var amount: BigInt {
        switch self {
        case .GasFee(_, _, let amount):
            return amount
        case .Eip1559(_, _, _, let amount):
            return amount
        case .BasicFee(let amount):
            return amount
        }
    }
}

protocol FeeService {
    func calculateFees(chain: Chain, limit: BigInt, isSwap: Bool, gasPrice: BigInt, priorityFee: BigInt) async throws -> FeeEnum
}

class EthereumFeeService: FeeService {
    
    private let rpcEvmService: RpcEvmService
    
    init(rpcEvmService: RpcEvmService) {
        self.rpcEvmService = rpcEvmService
    }
    
    func calculateFees(chain: Chain, limit: BigInt, isSwap: Bool, gasPrice: BigInt, priorityFee: BigInt) async throws -> FeeEnum {
        
        if chain.supportsEip1559 {
            return try await calculateEip1559Fees(limit: limit, isSwap: isSwap, priorityFee: priorityFee)
        } else {
            return calculateLegacyFees(limit: limit, isSwap: isSwap, gasPrice: gasPrice)
        }
    }
    
    private func calculateEip1559Fees(limit: BigInt, isSwap: Bool, priorityFee: BigInt) async throws -> FeeEnum {
        let baseFee = try await rpcEvmService.getBaseFee()
        
        if isSwap {
            let adjustedBaseFee = baseFee * 110 / 100
            let adjustedPriorityFee = priorityFee * 110 / 100
            let maxFeePerGas = (adjustedBaseFee * 120 / 100) + adjustedPriorityFee
            
            return .Eip1559(
                limit: limit,
                maxFeePerGas: maxFeePerGas,
                maxPriorityFeePerGas: adjustedPriorityFee,
                amount: limit * maxFeePerGas
            )
        } else {
            let maxFeePerGas = baseFee + priorityFee
            
            return .Eip1559(
                limit: limit,
                maxFeePerGas: maxFeePerGas,
                maxPriorityFeePerGas: priorityFee,
                amount: limit * maxFeePerGas
            )
        }
    }
    
    private func calculateLegacyFees(limit: BigInt, isSwap: Bool, gasPrice: BigInt) -> FeeEnum {
        let adjustedGasPrice = isSwap ? gasPrice * 110 / 100 : gasPrice
        let amount = adjustedGasPrice * limit
        
        return .GasFee(
            price: adjustedGasPrice,
            limit: limit,
            amount: amount
        )
    }
    
    func calculateFeesLegacy(chain: Chain, specific: BlockChainSpecific, isSwap: Bool, gasPrice: BigInt, priorityFee: BigInt) async throws -> (gas: String, priorityFee: String) {
        
        let gasLimit = BigInt(specific.gas)
        let fee = try await calculateFees(chain: chain, limit: gasLimit, isSwap: isSwap, gasPrice: gasPrice, priorityFee: priorityFee)
        
        switch fee {
        case .Eip1559(_, _, let maxPriorityFeePerGas, let amount):
            return (gas: String(amount), priorityFee: String(maxPriorityFeePerGas))
        case .GasFee(_, _, let amount):
            return (gas: String(amount), priorityFee: "0")
        case .BasicFee(let amount):
            return (gas: String(amount), priorityFee: "0")
        }
    }
}

enum FeeServiceError: Error {
    case invalidResponse
    case unsupportedChain
}
