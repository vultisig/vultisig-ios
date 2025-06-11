//
//  KyberSwapQuote.swift
//  VultisigApp
//
//  Created by AI Assistant on [Current Date].
//

import Foundation

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
    
    // Computed properties to match OneInch interface for compatibility
    var dstAmount: String {
        return data.amountOut
    }
    
    var tx: Transaction {
        // Apply conservative universal buffer for quote display
        // Chain-specific buffers are handled in KyberSwapService for actual transactions
        let baseGas = Int64(data.gas) ?? 600000 // Use 600k fallback (same as EVMHelper.defaultETHSwapGasUnit)
        let gasBuffer = Double(baseGas) * 0.4 // 40% conservative buffer for display
        let bufferedGas = Int64(Double(baseGas) + gasBuffer)
        
        return Transaction(
            from: "", // Will be filled by the service
            to: data.routerAddress,
            data: data.data,
            value: data.transactionValue,
            gasPrice: data.gasPrice ?? "20000000000", // Use provided gasPrice or 20 Gwei default
            gas: bufferedGas
        )
    }
}

// Transaction structure to maintain compatibility with OneInch interface
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
            self.gas = gas == 0 ? 600000 : gas // Use 600k fallback (same as EVMHelper.defaultETHSwapGasUnit)
        }
    }
} 