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
        let additionalCostUsd: String?
        let additionalCostMessage: String?
        var gasPrice: String?
        
        init(amountIn: String, amountInUsd: String, amountOut: String, amountOutUsd: String, gas: String, gasUsd: String, data: String, routerAddress: String, transactionValue: String, additionalCostUsd: String? = nil, additionalCostMessage: String? = nil, gasPrice: String? = nil) {
            self.amountIn = amountIn
            self.amountInUsd = amountInUsd
            self.amountOut = amountOut
            self.amountOutUsd = amountOutUsd
            self.gas = gas
            self.gasUsd = gasUsd
            self.data = data
            self.routerAddress = routerAddress
            self.transactionValue = transactionValue
            self.additionalCostUsd = additionalCostUsd
            self.additionalCostMessage = additionalCostMessage
            self.gasPrice = gasPrice
        }
    }
    
    let code: Int
    let message: String
    var data: Data
    let requestId: String
    
    var dstAmount: String {
        return data.amountOut
    }
    
    var tx: Transaction {
        let baseGas = Int64(data.gas) ?? 600000
        let bufferedGas = (baseGas * 14) / 10
        
        let gasPriceValue = data.gasPrice ?? "20000000000"
        let gasPriceBigInt = BigInt(gasPriceValue) ?? BigInt("20000000000")
        let minGasPrice = BigInt("1000000000")
        let finalGasPrice = gasPriceBigInt < minGasPrice ? minGasPrice : gasPriceBigInt
        
        return Transaction(
            from: "",
            to: data.routerAddress,
            data: data.data,
            value: data.transactionValue,
            gasPrice: finalGasPrice.description,
            gas: bufferedGas
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
            self.gas = gas == 0 ? 600000 : gas
        }
    }
} 