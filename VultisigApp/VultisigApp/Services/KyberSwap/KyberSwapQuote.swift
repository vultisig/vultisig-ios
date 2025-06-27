//
//  KyberSwapQuote.swift
//  VultisigApp
//
//  Created by Enrique Souza on 11.06.2025.
//

import Foundation
import BigInt

struct KyberSwapQuote: Codable, Hashable {
    struct Data: Codable, Hashable {
        let amountIn: String
        let amountInUsd: String
        let amountOut: String
        let amountOutUsd: String
        let gas: String
        let gasUsd: String
        let data: String
        let routerAddress: String
        let transactionValue: String
        var gasPrice: String?
    }
    
    let code: Int
    let message: String
    var data: Data
    let requestId: String
    
    var dstAmount: String {
        return data.amountOut
    }
    
    func gasForChain(_ chain: Chain) -> Int64 {
        let baseGas = Int64(data.gas) ?? 600000
        let gasMultiplierTimes10: Int64
        
        switch chain {
        case .ethereum:
            gasMultiplierTimes10 = 14
        case .arbitrum, .optimism, .base, .polygon, .avalanche, .bscChain:
            gasMultiplierTimes10 = 20
        default:
            gasMultiplierTimes10 = 16
        }
        
        return (baseGas * gasMultiplierTimes10) / 10
    }
    
    var tx: Transaction {
        
        return Transaction(
            from: "",
            to: data.routerAddress,
            data: data.data,
            value: data.transactionValue,
            gasPrice: data.gasPrice ?? "",
            gas: Int64(data.gas) ?? 0
        )
    }
}

extension KyberSwapQuote {
    struct Transaction: Codable, Hashable {
        let from: String
        let to: String
        let data: String
        let value: String
        let gasPrice: String
        let gas: Int64
        
        init(from: String, to: String, data: String, value: String, gasPrice: String, gas: Int64) {
            self.from = from
            self.to = to
            self.data = data
            self.value = value
            self.gasPrice = gasPrice
            self.gas = gas
        }
    }
} 
