//
//  FeeService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 03/09/25.
//

import Foundation
import BigInt
import VultisigCommonData

protocol Fee {
    var amount: BigInt { get }
}

struct GasFees: Fee {
    let price: BigInt
    let limit: BigInt
    let amount: BigInt
    
    init(price: BigInt, limit: BigInt) {
        self.price = price
        self.limit = limit
        self.amount = price * limit
    }
}

struct Eip1559: Fee {
    let limit: BigInt
    let maxFeePerGas: BigInt
    let maxPriorityFeePerGas: BigInt
    let amount: BigInt
    
    init(limit: BigInt, maxFeePerGas: BigInt, maxPriorityFeePerGas: BigInt) {
        self.limit = limit
        self.maxFeePerGas = maxFeePerGas
        self.maxPriorityFeePerGas = maxPriorityFeePerGas
        self.amount = limit * maxFeePerGas
    }
}

struct BasicFee: Fee {
    let amount: BigInt
    
    init(amount: BigInt) {
        self.amount = amount
    }
}

protocol FeeService {
    func calculateFees(chain: Chain, limit: BigInt, isSwap: Bool) async throws -> Fee
}

class EthereumFeeService: FeeService {
    
    private let rpcEvmService: RpcEvmService
    
    init(rpcEvmService: RpcEvmService) {
        self.rpcEvmService = rpcEvmService
    }
    
    func calculateFees(chain: Chain, limit: BigInt, isSwap: Bool) async throws -> Fee {

        let baseFee = try await rpcEvmService.getBaseFee()
        let priorityFee = try await rpcEvmService.fetchMaxPriorityFeePerGas()
        
        let adjustedBaseFee = isSwap ? baseFee * 2 : baseFee
        let adjustedPriorityFee = isSwap ? priorityFee * 2 : priorityFee
        
        let maxFeePerGas = adjustedBaseFee + adjustedPriorityFee
        
        return Eip1559(
            limit: limit,
            maxFeePerGas: maxFeePerGas,
            maxPriorityFeePerGas: adjustedPriorityFee
        )
    }

    func calculateFeesLegacy(chain: Chain, specific: BlockChainSpecific, isSwap: Bool) async throws -> (gas: String, priorityFee: String) {
        
        let gasLimit = BigInt(specific.gas)
        let fee = try await calculateFees(chain: chain, limit: gasLimit, isSwap: isSwap)
        
        switch fee {
        case let eip1559 as Eip1559:
            return (gas: String(eip1559.amount), priorityFee: String(eip1559.maxPriorityFeePerGas))
        case let gasFees as GasFees:
            return (gas: String(gasFees.amount), priorityFee: "0")
        case let basicFee as BasicFee:
            return (gas: String(basicFee.amount), priorityFee: "0")
        default:
            return (gas: String(fee.amount), priorityFee: "0")
        }
    }
}

enum FeeServiceError: Error {
    case invalidResponse
    case unsupportedChain
}
